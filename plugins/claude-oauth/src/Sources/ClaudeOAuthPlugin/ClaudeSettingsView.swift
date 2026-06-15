import SwiftUI
import AppKit
import TypeWhisperPluginSDK

struct ClaudeSettingsView: View {
    let host: HostServices
    let oauthClient: OAuthClient

    @State private var state: ConnectionState = .idle
    @State private var pkce: PKCEPair?
    @State private var stateNonce: String = ""
    @State private var codeInput: String = ""
    @State private var loadedTokens: TokenSet?
    @State private var selectedModel: String = ClaudeOAuthLLMPlugin.defaultModel
    @State private var errorMessage: String?
    @State private var isWorking: Bool = false

    private enum ConnectionState: Equatable {
        case idle
        case awaitingCode
        case connected
        case expired
    }

    /// Re-read the keychain every 30s so the displayed "Token gültig bis" date updates
    /// when the background refresh scheduler rotates the token.
    private let liveRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude (OAuth Pro/Max)").font(.title2).bold()

            switch state {
            case .idle: idleView
            case .awaitingCode: codeEntryView
            case .connected: connectedView
            case .expired: expiredView
            }

            if let errorMessage {
                Text(errorMessage).foregroundColor(.red).font(.callout)
            }
        }
        .padding(20)
        .frame(maxWidth: 560, alignment: .leading)
        .onAppear { loadInitialState() }
        .onReceive(liveRefreshTimer) { _ in refreshDisplayedTokens() }
    }

    // MARK: - Subviews

    private var idleView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("● Nicht verbunden")
            Text("Verbinde dein Claude Pro/Max-Abo, um Claude für Textaufbereitung zu nutzen. Es entstehen keine zusätzlichen Kosten – nur dein bestehendes Abo.")
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(.secondary)
            Button("Mit Claude verbinden") { startLogin() }
                .disabled(isWorking)
        }
    }

    private var codeEntryView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Browser wurde geöffnet. Logge dich bei Claude ein, bestätige die Berechtigung und kopiere den Code, der dir angezeigt wird, in das folgende Feld:")
                .fixedSize(horizontal: false, vertical: true)
            TextField("Authorization Code", text: $codeInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Abbrechen") { cancelLogin() }.disabled(isWorking)
                Spacer()
                Button("Bestätigen") { confirmCode() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(isWorking || codeInput.isEmpty)
            }
        }
    }

    private var connectedView: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let email = loadedTokens?.accountEmail {
                Text("● Verbunden als \(email)")
            } else {
                Text("● Verbunden")
            }
            if let expiresAt = loadedTokens?.expiresAt {
                Text("Token gültig bis: \(expiresAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
            HStack {
                Text("Modell:")
                Picker("", selection: $selectedModel) {
                    Text("Haiku 4.5 — schnell").tag("claude-haiku-4-5")
                    Text("Sonnet 4.6 — ausgewogen").tag("claude-sonnet-4-6")
                    Text("Opus 4.7 — präzise").tag("claude-opus-4-7")
                }
                .labelsHidden()
                .onChange(of: selectedModel) { _, newValue in
                    host.setUserDefault(newValue, forKey: ClaudeOAuthLLMPlugin.selectedModelKey)
                }
            }
            HStack {
                Button("Verbindung testen") { Task { await testConnection() } }.disabled(isWorking)
                Spacer()
                Button("Trennen", role: .destructive) { disconnect() }.disabled(isWorking)
            }
        }
    }

    private var expiredView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("● Token abgelaufen").foregroundColor(.orange)
            Text("Deine Sitzung ist abgelaufen und konnte nicht automatisch erneuert werden. Bitte verbinde dich erneut.")
                .fixedSize(horizontal: false, vertical: true)
            Button("Erneut verbinden") { startLogin() }.disabled(isWorking)
        }
    }

    // MARK: - Actions

    private func loadInitialState() {
        loadedTokens = TokenStore(host: host).load()
        selectedModel = (host.userDefault(forKey: ClaudeOAuthLLMPlugin.selectedModelKey) as? String)
            ?? ClaudeOAuthLLMPlugin.defaultModel
        state = (loadedTokens == nil) ? .idle : .connected
    }

    /// Reload tokens from the keychain. Called periodically so the displayed expiry date
    /// reflects background refreshes. Only updates when we're in a connected/expired state —
    /// avoids clobbering the login UI mid-flow.
    private func refreshDisplayedTokens() {
        guard state == .connected || state == .expired else { return }
        let fresh = TokenStore(host: host).load()
        if let fresh {
            loadedTokens = fresh
            if state == .expired { state = .connected }
        } else {
            loadedTokens = nil
            state = .idle
        }
    }

    private func startLogin() {
        errorMessage = nil
        let pair = PKCEPair.generate()
        let nonce = UUID().uuidString
        self.pkce = pair
        self.stateNonce = nonce
        let url = OAuthURLBuilder.authorizationURL(challenge: pair.challenge, state: nonce)
        NSWorkspace.shared.open(url)
        codeInput = ""
        state = .awaitingCode
    }

    private func cancelLogin() {
        pkce = nil
        stateNonce = ""
        codeInput = ""
        state = (loadedTokens == nil) ? .idle : .connected
    }

    private func confirmCode() {
        guard let pkce else { return }
        let trimmed = codeInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // Anthropic returns "<code>#<state>" — split into the two halves.
        let parts = trimmed.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
        let codePart = String(parts[0])
        let statePart = parts.count > 1 ? String(parts[1]) : nil

        // CSRF guard: the state we sent in the authorize URL must come back attached
        // to the code and match exactly. A missing or wrong state means the user is
        // pasting from a different (possibly attacker-initiated) authorization session
        // or a malformed copy.
        guard let returnedState = statePart else {
            errorMessage = "Code unvollständig — bitte den ganzen Code inklusive '#…' einfügen."
            return
        }
        guard returnedState == stateNonce else {
            errorMessage = "Code stimmt nicht zur Anmeldung — bitte 'Mit Claude verbinden' erneut starten."
            return
        }

        isWorking = true
        errorMessage = nil
        Task {
            do {
                let tokens = try await oauthClient.exchangeAuthorizationCode(
                    code: codePart,
                    verifier: pkce.verifier,
                    state: statePart
                )
                try TokenStore(host: host).save(tokens)
                await MainActor.run {
                    loadedTokens = tokens
                    state = .connected
                    isWorking = false
                    host.notifyCapabilitiesChanged()
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Code ungültig oder Server-Fehler: \(error.localizedDescription)"
                    isWorking = false
                }
            }
        }
    }

    private func testConnection() async {
        guard let tokens = loadedTokens else { return }
        await MainActor.run { isWorking = true; errorMessage = nil }
        let client = AnthropicClient()
        do {
            _ = try await client.send(
                accessToken: tokens.accessToken,
                model: selectedModel,
                systemPrompt: "Say OK.",
                userText: "ping"
            )
            await MainActor.run { errorMessage = "Verbindung erfolgreich getestet."; isWorking = false }
        } catch {
            await MainActor.run {
                errorMessage = "Test fehlgeschlagen: \(error.localizedDescription)"
                isWorking = false
            }
        }
    }

    private func disconnect() {
        try? TokenStore(host: host).clear()
        loadedTokens = nil
        state = .idle
        host.notifyCapabilitiesChanged()
    }
}

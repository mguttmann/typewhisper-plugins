import Foundation
import SwiftUI
import TypeWhisperPluginSDK

public enum PluginProcessError: Error, Equatable, Sendable {
    case notConfigured
    case authExpired
    case rateLimited(retryAfter: Int?)
    case invalidModel(String)
    case network(String)
    case apiError(String)
}

@objc(ClaudeOAuthLLMPlugin)
public final class ClaudeOAuthLLMPlugin: NSObject, LLMProviderPlugin, @unchecked Sendable {
    public static let pluginId = "com.guttmann.typewhisper-claude-oauth"
    public static let pluginName = "Claude (OAuth Pro/Max)"

    public static let defaultModel = "claude-haiku-4-5"
    public static let selectedModelKey = "selectedModel"

    private let oauthClient: OAuthClient
    private let anthropicClient: AnthropicClient
    private var host: HostServices?
    private var refreshTimer: RefreshTimer?

    public override convenience init() {
        self.init(oauthClient: OAuthClient(), anthropicClient: AnthropicClient())
    }

    public init(oauthClient: OAuthClient, anthropicClient: AnthropicClient) {
        self.oauthClient = oauthClient
        self.anthropicClient = anthropicClient
        super.init()
    }

    // MARK: - TypeWhisperPlugin lifecycle

    public func activate(host: HostServices) {
        self.host = host
        // Start scheduler only if we already have tokens — otherwise no-op until user logs in.
        if currentTokens() != nil {
            startRefreshTimer()
            // Fire one immediate-threshold check off the main thread so a stale token
            // (e.g. after the app was killed for a while) is refreshed proactively
            // rather than on the next process() call's hot path.
            Task { [weak self] in await self?.scheduledRefreshCheck(host: host) }
        }
    }

    public func deactivate() {
        refreshTimer?.stop()
        refreshTimer = nil
        host = nil
    }

    public var settingsView: AnyView? {
        guard let host else { return nil }
        return AnyView(ClaudeSettingsView(host: host, oauthClient: oauthClient))
    }

    // MARK: - LLMProviderPlugin

    public var providerName: String { "Claude (OAuth Pro/Max)" }

    public var isAvailable: Bool { currentTokens() != nil }

    public var supportedModels: [PluginModelInfo] {
        [
            PluginModelInfo(id: "claude-haiku-4-5",  displayName: "Haiku 4.5 — schnell"),
            PluginModelInfo(id: "claude-sonnet-4-6", displayName: "Sonnet 4.6 — ausgewogen"),
            PluginModelInfo(id: "claude-opus-4-7",   displayName: "Opus 4.7 — präzise"),
        ]
    }

    public func process(systemPrompt: String, userText: String, model: String?) async throws -> String {
        guard let host else { throw PluginProcessError.notConfigured }
        let store = TokenStore(host: host)
        guard var tokens = store.load() else { throw PluginProcessError.notConfigured }

        // Refresh immediately if we're within the immediate threshold (5 min).
        if RefreshScheduler.needsRefresh(tokens: tokens, threshold: .immediate) {
            tokens = try await refreshAndPersist(currentTokens: tokens, store: store)
        }

        let chosenModel = model
            ?? (host.userDefault(forKey: Self.selectedModelKey) as? String)
            ?? Self.defaultModel

        do {
            // sendAndMap maps all AnthropicErrors EXCEPT authExpired to PluginProcessError.
            // authExpired propagates so we can catch it below and trigger refresh + retry.
            return try await sendAndMap(
                accessToken: tokens.accessToken,
                model: chosenModel,
                systemPrompt: systemPrompt,
                userText: userText
            )
        } catch AnthropicError.authExpired {
            // Token was rejected mid-flight (e.g. revoked) — refresh once and retry.
            do {
                tokens = try await refreshAndPersist(currentTokens: tokens, store: store)
            } catch {
                throw PluginProcessError.authExpired
            }
            // Any error from the retry is also mapped to PluginProcessError via sendAndMap.
            return try await sendAndMap(
                accessToken: tokens.accessToken,
                model: chosenModel,
                systemPrompt: systemPrompt,
                userText: userText
            )
        }
    }

    /// Calls `anthropicClient.send` and maps all `AnthropicError` cases — except `authExpired` —
    /// to `PluginProcessError`. `authExpired` is intentionally left unmapped so `process()` can
    /// catch it and trigger a token refresh before retrying.
    private func sendAndMap(
        accessToken: String,
        model: String,
        systemPrompt: String,
        userText: String
    ) async throws -> String {
        do {
            return try await anthropicClient.send(
                accessToken: accessToken,
                model: model,
                systemPrompt: systemPrompt,
                userText: userText
            )
        } catch let AnthropicError.rateLimited(retryAfter) {
            throw PluginProcessError.rateLimited(retryAfter: retryAfter)
        } catch let AnthropicError.invalidModel(message) {
            throw PluginProcessError.invalidModel(message)
        } catch let AnthropicError.network(message) {
            throw PluginProcessError.network(message)
        } catch let AnthropicError.apiError(_, body) {
            throw PluginProcessError.apiError(body)
        } catch AnthropicError.malformedResponse {
            throw PluginProcessError.apiError("Malformed response from Anthropic")
        }
        // Note: AnthropicError.authExpired is NOT caught here — it propagates to process().
    }

    // MARK: - Internal helpers

    internal func refreshAndPersist(currentTokens: TokenSet, store: TokenStore) async throws -> TokenSet {
        let refreshed: TokenSet
        do {
            refreshed = try await oauthClient.refresh(
                refreshToken: currentTokens.refreshToken,
                previousEmail: currentTokens.accountEmail
            )
        } catch OAuthError.invalidGrant {
            throw PluginProcessError.authExpired
        } catch let OAuthError.network(message) {
            throw PluginProcessError.network(message)
        } catch {
            throw PluginProcessError.apiError(String(describing: error))
        }
        try store.save(refreshed)
        return refreshed
    }

    private func currentTokens() -> TokenSet? {
        guard let host else { return nil }
        return TokenStore(host: host).load()
    }

    private func startRefreshTimer() {
        guard let host else { return }
        let timer = RefreshTimer { [weak self] in
            Task { await self?.scheduledRefreshCheck(host: host) }
        }
        timer.start()
        self.refreshTimer = timer
    }

    private func scheduledRefreshCheck(host: HostServices) async {
        let store = TokenStore(host: host)
        guard let tokens = store.load() else { return }
        guard RefreshScheduler.needsRefresh(tokens: tokens, threshold: .scheduler) else { return }
        _ = try? await refreshAndPersist(currentTokens: tokens, store: store)
    }
}

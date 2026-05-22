import Foundation

public enum OAuthError: Error, Equatable, Sendable {
    case invalidGrant
    case httpError(status: Int, body: String)
    case network(String)
    case malformedResponse
}

public final class OAuthClient: @unchecked Sendable {
    private let session: URLSession
    private let retryDelays: [TimeInterval]

    /// `retryDelays`: backoff (seconds) before retry attempts 1..N. Default `[2, 4, 6]` matches claude-seat-rotator.
    /// Use `[]` in tests to disable retries (e.g. asserting first-call behaviour) or `[0, 0, 0]` for speed.
    public init(session: URLSession = .shared, retryDelays: [TimeInterval] = [2.0, 4.0, 6.0]) {
        self.session = session
        self.retryDelays = retryDelays
    }

    // MARK: - Exchange

    public func exchangeAuthorizationCode(code: String, verifier: String, state: String? = nil) async throws -> TokenSet {
        var body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConstants.redirectURI,
            "client_id": OAuthConstants.clientID,
            "code_verifier": verifier,
        ]
        if let state { body["state"] = state }
        let response: OAuthTokenResponse = try await postOnce(body: body)
        guard let refresh = response.refreshToken else { throw OAuthError.malformedResponse }
        return TokenSet(
            accessToken: response.accessToken,
            refreshToken: refresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountEmail: response.account?.emailAddress
        )
    }

    // MARK: - Refresh (with retry on transient failures)

    public func refresh(refreshToken: String, previousEmail: String?) async throws -> TokenSet {
        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConstants.clientID,
        ]
        let response: OAuthTokenResponse = try await postWithRetry(body: body)
        // Anthropic's refresh tokens are single-use: a successful refresh always returns a
        // new refresh_token, and the request just made consumed the old one. If the response
        // omits the new token (truncated payload, server bug, etc.) the old one is already
        // dead — falling back to it would silently store a token that errors on next use.
        guard let newRefresh = response.refreshToken else {
            throw OAuthError.malformedResponse
        }
        return TokenSet(
            accessToken: response.accessToken,
            refreshToken: newRefresh,
            expiresAt: Date().addingTimeInterval(TimeInterval(response.expiresIn)),
            accountEmail: response.account?.emailAddress ?? previousEmail
        )
    }

    // MARK: - Network primitives

    private func postOnce(body: [String: String]) async throws -> OAuthTokenResponse {
        try await sendOnce(body: body)
    }

    private func postWithRetry(body: [String: String]) async throws -> OAuthTokenResponse {
        var lastError: OAuthError = .malformedResponse
        let attempts = retryDelays.count + 1
        for attempt in 0..<attempts {
            do {
                return try await sendOnce(body: body)
            } catch let error as OAuthError {
                if !isTransient(error) { throw error }
                lastError = error
                if attempt < retryDelays.count {
                    try await Task.sleep(nanoseconds: UInt64(retryDelays[attempt] * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    private func sendOnce(body: [String: String]) async throws -> OAuthTokenResponse {
        var request = URLRequest(url: URL(string: OAuthConstants.tokenEndpoint)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 20
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let urlResponse: URLResponse
        do { (data, urlResponse) = try await session.data(for: request) }
        catch { throw OAuthError.network(error.localizedDescription) }

        guard let http = urlResponse as? HTTPURLResponse else { throw OAuthError.malformedResponse }
        switch http.statusCode {
        case 200..<300:
            do { return try JSONDecoder().decode(OAuthTokenResponse.self, from: data) }
            catch { throw OAuthError.malformedResponse }
        case 400:
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               json["error"] as? String == "invalid_grant" {
                throw OAuthError.invalidGrant
            }
            throw OAuthError.httpError(status: 400, body: String(data: data, encoding: .utf8) ?? "")
        default:
            throw OAuthError.httpError(status: http.statusCode, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    private func isTransient(_ error: OAuthError) -> Bool {
        switch error {
        case .network: return true
        case .httpError(let status, _): return status == 429 || status >= 500
        case .invalidGrant, .malformedResponse: return false
        }
    }
}

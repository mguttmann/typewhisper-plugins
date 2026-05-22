import Foundation
import os.log

private let logger = Logger(subsystem: "com.guttmann.typewhisper-claude-oauth", category: "anthropic-client")

public enum AnthropicError: Error, Equatable, Sendable {
    case authExpired
    case rateLimited(retryAfter: Int?)
    case invalidModel(String)
    case apiError(status: Int, body: String)
    case network(String)
    case malformedResponse
}

public final class AnthropicClient: @unchecked Sendable {
    private let session: URLSession
    private let retryDelays: [TimeInterval]

    /// `retryDelays`: backoff (seconds) before each retry attempt. Default `[1.0, 2.0]` means
    /// up to 2 retries (3 total attempts) on transient failures (network errors, HTTP 5xx).
    /// Pass `[]` to disable retries entirely.
    public init(session: URLSession = .shared, retryDelays: [TimeInterval] = [1.0, 2.0]) {
        self.session = session
        self.retryDelays = retryDelays
    }

    public func send(accessToken: String, model: String, systemPrompt: String, userText: String) async throws -> String {
        logger.info("→ send model=\(model, privacy: .public) systemPrompt.count=\(systemPrompt.count) userText.count=\(userText.count)")
        let request = try AnthropicRequestBuilder.messagesRequest(
            accessToken: accessToken,
            model: model,
            systemPrompt: systemPrompt,
            userText: userText
        )

        var lastError: AnthropicError = .malformedResponse
        let attempts = retryDelays.count + 1
        for attempt in 0..<attempts {
            do {
                return try await sendOnce(request: request)
            } catch let error as AnthropicError where isTransient(error) {
                lastError = error
                if attempt < retryDelays.count {
                    let delay = retryDelays[attempt]
                    logger.info("Transient error (\(String(describing: error), privacy: .public)), retry \(attempt + 1)/\(self.retryDelays.count) in \(delay)s")
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    private func isTransient(_ error: AnthropicError) -> Bool {
        switch error {
        case .network: return true
        case .apiError(let status, _): return status >= 500
        case .rateLimited, .authExpired, .invalidModel, .malformedResponse: return false
        }
    }

    private func sendOnce(request: URLRequest) async throws -> String {
        let data: Data
        let urlResponse: URLResponse
        do { (data, urlResponse) = try await session.data(for: request) }
        catch {
            logger.error("Network error: \(error.localizedDescription, privacy: .public)")
            throw AnthropicError.network(error.localizedDescription)
        }

        guard let http = urlResponse as? HTTPURLResponse else { throw AnthropicError.malformedResponse }
        logger.info("← status=\(http.statusCode) body.count=\(data.count)")
        switch http.statusCode {
        case 200..<300:
            let decoded = try? JSONDecoder().decode(MessagesResponse.self, from: data)
            guard let text = decoded?.firstTextBlock else {
                let preview = String(data: data, encoding: .utf8)?.prefix(500) ?? ""
                logger.error("Malformed 2xx response: \(preview, privacy: .public)")
                throw AnthropicError.malformedResponse
            }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case 401, 403:
            let bodyText = String(data: data, encoding: .utf8) ?? ""
            logger.error("authExpired status=\(http.statusCode) body=\(bodyText, privacy: .public)")
            throw AnthropicError.authExpired
        case 429:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            logger.error("rateLimited retryAfter=\(retryAfter ?? -1)")
            throw AnthropicError.rateLimited(retryAfter: retryAfter)
        case 400:
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("400 body=\(body, privacy: .public)")
            let parsed = try? JSONDecoder().decode(AnthropicErrorResponse.self, from: data)
            if let message = parsed?.error.message, message.lowercased().contains("model") {
                throw AnthropicError.invalidModel(message)
            }
            throw AnthropicError.apiError(status: 400, body: body)
        default:
            let body = String(data: data, encoding: .utf8) ?? ""
            logger.error("API error status=\(http.statusCode) body=\(body, privacy: .public)")
            throw AnthropicError.apiError(status: http.statusCode, body: body)
        }
    }
}

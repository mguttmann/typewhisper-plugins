import Foundation

public enum AnthropicRequestBuilder {
    public static let messagesEndpoint = "https://api.anthropic.com/v1/messages"
    public static let claudeCodeIdentity = "You are Claude Code, Anthropic's official CLI for Claude."
    public static let defaultMaxTokens = 2048
    public static let defaultTemperature = 0.3
    public static let requestTimeout: TimeInterval = 60

    public static func messagesRequest(
        accessToken: String,
        model: String,
        systemPrompt: String,
        userText: String
    ) throws -> URLRequest {
        var request = URLRequest(url: URL(string: messagesEndpoint)!)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(OAuthConstants.anthropicBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.setValue(OAuthConstants.anthropicVersionHeader, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "model": model,
            "max_tokens": defaultMaxTokens,
            "system": [
                ["type": "text", "text": claudeCodeIdentity],
                ["type": "text", "text": systemPrompt],
            ],
            "messages": [
                ["role": "user", "content": userText],
            ],
        ]
        if modelAcceptsTemperature(model) {
            body["temperature"] = defaultTemperature
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    /// Whether the given model accepts the `temperature` parameter. Newer reasoning models
    /// (Opus 4.7+) reject it with a 400 "deprecated for this model" error.
    public static func modelAcceptsTemperature(_ model: String) -> Bool {
        !model.hasPrefix("claude-opus-4-7")
    }
}

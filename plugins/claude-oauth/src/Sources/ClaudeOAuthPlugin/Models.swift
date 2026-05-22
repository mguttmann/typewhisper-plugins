import Foundation

// MARK: - Persisted token state

public struct TokenSet: Codable, Sendable, Equatable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let accountEmail: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, accountEmail: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.accountEmail = accountEmail
    }
}

// MARK: - OAuth token endpoint response (Anthropic)

public struct OAuthTokenResponse: Decodable, Sendable {
    public struct Account: Decodable, Sendable {
        public let emailAddress: String?
        public let uuid: String?

        enum CodingKeys: String, CodingKey {
            case emailAddress = "email_address"
            case uuid
        }
    }

    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int
    public let account: Account?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case account
    }
}

// MARK: - Anthropic Messages API

public struct MessagesResponse: Decodable, Sendable {
    public struct ContentBlock: Decodable, Sendable {
        public let type: String
        public let text: String?
    }

    public let id: String
    public let content: [ContentBlock]

    public var firstTextBlock: String? {
        content.first(where: { $0.type == "text" })?.text
    }
}

public struct AnthropicErrorResponse: Decodable, Sendable {
    public struct ErrorBody: Decodable, Sendable {
        public let type: String
        public let message: String
    }
    public let error: ErrorBody
}

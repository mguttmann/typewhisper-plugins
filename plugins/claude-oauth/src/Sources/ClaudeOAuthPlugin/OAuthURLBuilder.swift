import Foundation

public enum OAuthConstants {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizationEndpoint = "https://claude.ai/oauth/authorize"
    public static let tokenEndpoint = "https://platform.claude.com/v1/oauth/token"
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scope = "org:create_api_key user:profile user:inference"
    public static let anthropicBetaHeader = "oauth-2025-04-20"
    public static let anthropicVersionHeader = "2023-06-01"
}

public enum OAuthURLBuilder {
    public static func authorizationURL(challenge: String, state: String) -> URL {
        var components = URLComponents(string: OAuthConstants.authorizationEndpoint)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: OAuthConstants.clientID),
            URLQueryItem(name: "redirect_uri", value: OAuthConstants.redirectURI),
            URLQueryItem(name: "scope", value: OAuthConstants.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }
}

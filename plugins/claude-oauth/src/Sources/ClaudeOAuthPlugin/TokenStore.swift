import Foundation
import TypeWhisperPluginSDK

public final class TokenStore: @unchecked Sendable {
    public static let secretKey = "com.guttmann.typewhisper-claude.oauth"

    private let host: HostServices
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(host: HostServices) {
        self.host = host
        self.encoder = JSONEncoder()
        self.encoder.dateEncodingStrategy = .millisecondsSince1970
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .millisecondsSince1970
    }

    public func save(_ tokens: TokenSet) throws {
        let data = try encoder.encode(tokens)
        guard let json = String(data: data, encoding: .utf8) else {
            throw TokenStoreError.encodingFailed
        }
        try host.storeSecret(key: Self.secretKey, value: json)
    }

    public func load() -> TokenSet? {
        guard let json = host.loadSecret(key: Self.secretKey),
              let data = json.data(using: .utf8) else { return nil }
        return try? decoder.decode(TokenSet.self, from: data)
    }

    public func clear() throws {
        try host.storeSecret(key: Self.secretKey, value: "")
    }
}

public enum TokenStoreError: Error, Sendable {
    case encodingFailed
}

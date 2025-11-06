import Foundation
import Security

public class KeychainTokenStorage: TokenStorage {
    private let service: String
    private let account: String

    public init(clientId: String, service: String? = nil) {
        self.service = service ?? "com.oauthkit.tokens"
        account = clientId
    }

    public func store(_ token: OAuthToken) async throws {
        let data = try JSONEncoder().encode(token)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]

        SecItemDelete(query as CFDictionary)

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.storeFailed(status)
        }
    }

    public func retrieve() async throws -> OAuthToken? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess else {
            if status == errSecItemNotFound {
                return nil
            }
            throw KeychainError.retrieveFailed(status)
        }

        guard let data = item as? Data else {
            throw KeychainError.invalidData
        }

        return try JSONDecoder().decode(OAuthToken.self, from: data)
    }

    public func clear() async {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)
    }
}

public enum KeychainError: Error, LocalizedError {
    case storeFailed(OSStatus)
    case retrieveFailed(OSStatus)
    case invalidData

    public var errorDescription: String? {
        switch self {
        case let .storeFailed(status):
            "Failed to store token in keychain (status: \(status))"
        case let .retrieveFailed(status):
            "Failed to retrieve token from keychain (status: \(status))"
        case .invalidData:
            "Invalid data retrieved from keychain"
        }
    }
}

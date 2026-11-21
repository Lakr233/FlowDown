//
//  MCPOAuthStore.swift
//  FlowDown
//

import Foundation
import os
import Security
import Storage

/// The OAuth client FlowDown uses for one server: either registered
/// dynamically (RFC 7591) or typed in by hand.
struct MCPOAuthClientRecord: Codable, Equatable {
    enum Source: String, Codable {
        case manual
        case dynamic
    }

    var clientID: String
    var clientSecret: String?
    /// `client_secret_basic`, `client_secret_post` or `none`.
    var tokenEndpointAuthMethod: String
    var source: Source
    /// Authorization server the dynamic registration belongs to. A manual
    /// client is not tied to one.
    var issuer: String?
    /// MCP endpoint the client was set up for. A client registered or typed
    /// in for one endpoint is never sent to another one.
    var endpoint: String

    func matches(endpoint: URL, issuer: URL?) -> Bool {
        guard self.endpoint == endpoint.absoluteString else { return false }
        guard source == .dynamic else { return true }
        guard let issuer, let own = self.issuer else { return false }
        return own == issuer.absoluteString
    }
}

/// Tokens for one server, bound to the endpoint and resource they were
/// issued for.
struct MCPOAuthTokenRecord: Codable, Equatable {
    var endpoint: String
    var resource: String
    var issuer: String?
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date?
    var scopes: [String]
    var clientID: String?
    /// Where to send the refresh grant, so a refresh needs no discovery.
    var tokenEndpoint: String?

    func matches(endpoint: URL) -> Bool {
        self.endpoint == endpoint.absoluteString
    }

    func isExpired(now: Date = .now, skew: TimeInterval = 30) -> Bool {
        guard let expiresAt else { return false }
        // `!(a < b)`, not `>=`: see Date+BackDeployedComparison.swift.
        return !(now.addingTimeInterval(skew) < expiresAt)
    }
}

/// Where OAuth secrets live. Production uses the device Keychain; tests use
/// an in-memory store. Nothing here goes into the database, iCloud sync,
/// exports or UserDefaults.
protocol MCPOAuthStoring: AnyObject, Sendable {
    func tokens(for serverID: ModelContextServer.ID) -> MCPOAuthTokenRecord?
    /// Returns false when the item couldn't be saved or removed.
    @discardableResult
    func setTokens(_ record: MCPOAuthTokenRecord?, for serverID: ModelContextServer.ID) -> Bool
    func client(for serverID: ModelContextServer.ID) -> MCPOAuthClientRecord?
    func setClient(_ record: MCPOAuthClientRecord?, for serverID: ModelContextServer.ID)
    /// Every server that has at least one stored item.
    func storedServerIDs() -> Set<ModelContextServer.ID>
}

extension MCPOAuthStoring {
    func removeAll(for serverID: ModelContextServer.ID) {
        setTokens(nil, for: serverID)
        setClient(nil, for: serverID)
    }
}

// MARK: - Keychain

/// Generic-password items, one per server and kind, that never leave this
/// device: not synchronizable (no iCloud Keychain) and
/// `AfterFirstUnlockThisDeviceOnly` (not restored to other hardware).
final class MCPOAuthKeychainStore: MCPOAuthStoring, @unchecked Sendable {
    static let shared = MCPOAuthKeychainStore(service: "wiki.qaq.flow.mcp-oauth")

    let service: String
    private let lock = OSAllocatedUnfairLock()

    init(service: String) {
        self.service = service
    }

    private enum Kind: String, CaseIterable {
        case tokens
        case client
    }

    private func account(_ serverID: ModelContextServer.ID, _ kind: Kind) -> String {
        "\(serverID)/\(kind.rawValue)"
    }

    private func baseQuery(account: String? = nil) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let account { query[kSecAttrAccount as String] = account }
        return query
    }

    func tokens(for serverID: ModelContextServer.ID) -> MCPOAuthTokenRecord? {
        read(account(serverID, .tokens))
    }

    @discardableResult
    func setTokens(_ record: MCPOAuthTokenRecord?, for serverID: ModelContextServer.ID) -> Bool {
        write(record, account: account(serverID, .tokens))
    }

    func client(for serverID: ModelContextServer.ID) -> MCPOAuthClientRecord? {
        read(account(serverID, .client))
    }

    func setClient(_ record: MCPOAuthClientRecord?, for serverID: ModelContextServer.ID) {
        write(record, account: account(serverID, .client))
    }

    func storedServerIDs() -> Set<ModelContextServer.ID> {
        var query = baseQuery()
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = lock.withLock { SecItemCopyMatching(query as CFDictionary, &result) }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { return [] }
        return Set(items.compactMap { item in
            guard let account = item[kSecAttrAccount as String] as? String,
                  let slash = account.lastIndex(of: "/")
            else { return nil }
            return String(account[..<slash])
        })
    }

    /// The stored item's protection attributes, for tests.
    func attributes(forTokensOf serverID: ModelContextServer.ID) -> [String: Any]? {
        var query = baseQuery(account: account(serverID, .tokens))
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnAttributes as String] = true
        var result: CFTypeRef?
        let status = lock.withLock { SecItemCopyMatching(query as CFDictionary, &result) }
        guard status == errSecSuccess else { return nil }
        return result as? [String: Any]
    }

    private func read<T: Decodable>(_ account: String) -> T? {
        var query = baseQuery(account: account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = lock.withLock { SecItemCopyMatching(query as CFDictionary, &result) }
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                Logger.network.errorFile("mcp oauth keychain read failed: \(status)")
            }
            return nil
        }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func write(_ value: (some Encodable)?, account: String) -> Bool {
        lock.withLock {
            let query = baseQuery(account: account)
            guard let value, let data = try? JSONEncoder().encode(value) else {
                let status = SecItemDelete(query as CFDictionary)
                if status != errSecSuccess, status != errSecItemNotFound {
                    Logger.network.errorFile("mcp oauth keychain delete failed: \(status)")
                    return false
                }
                return true
            }
            let attributes: [String: Any] = [
                kSecValueData as String: data,
                kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            ]
            var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
            if status == errSecItemNotFound {
                var insert = query
                insert.merge(attributes) { $1 }
                status = SecItemAdd(insert as CFDictionary, nil)
            }
            if status != errSecSuccess {
                Logger.network.errorFile("mcp oauth keychain write failed: \(status)")
                return false
            }
            return true
        }
    }
}

// MARK: - In Memory

final class MCPOAuthMemoryStore: MCPOAuthStoring, @unchecked Sendable {
    /// Simulates a Keychain that refuses token writes.
    let failsTokenWrites: Bool

    init(failsTokenWrites: Bool = false) {
        self.failsTokenWrites = failsTokenWrites
    }

    private let state = OSAllocatedUnfairLock(
        initialState: (
            tokens: [ModelContextServer.ID: MCPOAuthTokenRecord](),
            clients: [ModelContextServer.ID: MCPOAuthClientRecord](),
        ),
    )

    func tokens(for serverID: ModelContextServer.ID) -> MCPOAuthTokenRecord? {
        state.withLock { $0.tokens[serverID] }
    }

    @discardableResult
    func setTokens(_ record: MCPOAuthTokenRecord?, for serverID: ModelContextServer.ID) -> Bool {
        if failsTokenWrites, record != nil { return false }
        state.withLock { $0.tokens[serverID] = record }
        return true
    }

    func client(for serverID: ModelContextServer.ID) -> MCPOAuthClientRecord? {
        state.withLock { $0.clients[serverID] }
    }

    func setClient(_ record: MCPOAuthClientRecord?, for serverID: ModelContextServer.ID) {
        state.withLock { $0.clients[serverID] = record }
    }

    func storedServerIDs() -> Set<ModelContextServer.ID> {
        state.withLock { Set($0.tokens.keys).union($0.clients.keys) }
    }
}

@testable import FlowDown
import Foundation
import MCP
import os
import Security
import Storage
import Testing

@Suite(.serialized)
struct MCPOAuthTests {
    private func makeManager(_ server: MCPOAuthTestServer, store: MCPOAuthMemoryStore = .init()) -> (MCPOAuthManager, MCPOAuthStubPresenter) {
        let presenter = MCPOAuthStubPresenter(server: server)
        let manager = MCPOAuthManager(
            store: store,
            presenter: presenter,
            configureSession: { MCPOAuthStubProtocol.configure($0) },
        )
        return (manager, presenter)
    }

    private func makeServer(_ endpoint: URL, header: String = "") -> ModelContextServer {
        let server = ModelContextServer(name: "OAuth MCP", endpoint: endpoint.absoluteString)
        server.update(\.header, to: header)
        return server
    }

    private func connection(_ server: ModelContextServer, _ manager: MCPOAuthManager) -> MCPConnection {
        MCPConnection(config: server) { try $0.createTransport(oauth: manager) }
    }

    // MARK: - 401 Regression

    /// An unattended connect to a server that answers 401 fails promptly with
    /// sign-in required: no hang, no crash, no browser, no registration.
    @Test(.timeLimit(.minutes(1)))
    func unauthenticatedConnect_failsPromptlyWithoutUIOrRegistration() async throws {
        let backend = MCPOAuthTestServer()
        let (manager, presenter) = makeManager(backend)
        let server = makeServer(backend.endpoint)
        let connection = connection(server, manager)

        let clock = ContinuousClock()
        let started = clock.now
        await #expect(throws: (any Error).self) {
            try await connection.connect()
        }
        #expect(clock.now - started < .seconds(10))
        #expect(!connection.isConnected)
        #expect(manager.state(for: server.id) == .signInRequired)
        #expect(presenter.presentCount == 0)
        #expect(backend.count("/register") == 0)
        #expect(backend.count("/token") == 0)
    }

    /// The same 401 through `MCPService.testConnection` completes exactly
    /// once, with the sign-in error, which is what the editor's checked
    /// continuation relies on.
    @Test(.timeLimit(.minutes(1)))
    func testConnection401_completesOnceWithSignInRequired() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let backend = MCPOAuthTestServer()
        let (manager, presenter) = makeManager(backend)
        let service = MCPService.shared
        let originalOAuth = service.oauth
        service.oauth = manager
        let server = service.create { server in
            server.update(\.name, to: "OAuth Test MCP")
            server.update(\.endpoint, to: backend.endpoint.absoluteString)
            server.update(\.isEnabled, to: false)
        }
        defer {
            service.remove(server.id)
            service.oauth = originalOAuth
        }

        let completions = OSAllocatedUnfairLock(initialState: 0)
        let result: Result<String, Swift.Error> = await withCheckedContinuation { continuation in
            service.testConnection(serverID: server.id) { result in
                completions.withLock { $0 += 1 }
                continuation.resume(returning: result)
            }
        }
        try await Task.sleep(for: .milliseconds(500))
        #expect(completions.withLock { $0 } == 1)
        guard case let .failure(error) = result else {
            Issue.record("expected failure")
            return
        }
        #expect(error as? FlowDown.MCPError == .signInRequired(server.displayName))
        #expect(presenter.presentCount == 0)
        #expect(backend.count("/register") == 0)
        let committed = await MainActor.run { service.connections[server.id] != nil }
        #expect(!committed)
    }

    // MARK: - Sign-In

    @Test(.timeLimit(.minutes(1)))
    func signIn_registersAuthorizesWithPKCEAndConnects() async throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, presenter) = makeManager(backend, store: store)
        let server = makeServer(backend.endpoint)

        // The unattended attempt learns that sign-in is needed.
        await #expect(throws: (any Error).self) {
            try await connection(server, manager).connect()
        }
        #expect(manager.state(for: server.id) == .signInRequired)

        try await manager.signIn(server: server)
        #expect(presenter.presentCount == 1)
        #expect(backend.count("/register") == 1)
        #expect(manager.state(for: server.id) == .signedIn)

        let authorize = try #require(backend.state.withLock { $0.authorizeQueries.first })
        #expect(authorize["resource"] == backend.endpoint.absoluteString)
        #expect(authorize["redirect_uri"] == "flowdown://mcp-oauth/callback")
        #expect(authorize["code_challenge_method"] == "S256")
        #expect(authorize["scope"] == "mcp:tools")
        let tokenRequest = try #require(backend.state.withLock { $0.tokenRequests.first })
        #expect(tokenRequest["grant_type"] == "authorization_code")
        #expect(tokenRequest["resource"] == backend.endpoint.absoluteString)
        #expect(tokenRequest["code_verifier"] != nil)

        let tokens = try #require(store.tokens(for: server.id))
        #expect(tokens.endpoint == backend.endpoint.absoluteString)
        #expect(tokens.refreshToken != nil)
        #expect(store.client(for: server.id)?.source == .dynamic)

        let connected = connection(server, manager)
        try await connected.connect()
        defer { connected.disconnect() }
        let tools = try await connected.listToolInfos(serverID: server.id, serverName: "oauth")
        #expect(tools.map(\.name) == ["whoami"])
        #expect(backend.state.withLock { $0.authorizationHeaders.last } == "Bearer \(tokens.accessToken)")
        // A second sign-in reuses the stored registration.
        try await manager.signIn(server: server)
        #expect(backend.count("/register") == 1)
    }

    @Test(.timeLimit(.minutes(1)))
    func signIn_reportsKeychainFailureInsteadOfSigningIn() async throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore(failsTokenWrites: true)
        let (manager, _) = makeManager(backend, store: store)
        let server = makeServer(backend.endpoint)

        await #expect(throws: MCPOAuthError.keychainUnavailable) {
            try await manager.signIn(server: server)
        }
        #expect(manager.state(for: server.id) != .signedIn)
        #expect(store.tokens(for: server.id) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func expiredToken_isRefreshedBeforeConnecting() async throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, presenter) = makeManager(backend, store: store)
        let server = makeServer(backend.endpoint)
        backend.registerClient("existing-client")
        let issued = backend.issueTokens()
        store.setClient(
            .init(clientID: "existing-client", clientSecret: nil, tokenEndpointAuthMethod: "none",
                  source: .dynamic, issuer: backend.issuer.absoluteString, endpoint: backend.endpoint.absoluteString),
            for: server.id,
        )
        store.setTokens(
            .init(endpoint: backend.endpoint.absoluteString, resource: backend.endpoint.absoluteString,
                  issuer: backend.issuer.absoluteString, accessToken: "expired-token", refreshToken: issued.refresh,
                  expiresAt: .now.addingTimeInterval(-60), scopes: ["mcp:tools"], clientID: "existing-client",
                  tokenEndpoint: "https://\(backend.authHost)/token"),
            for: server.id,
        )

        let connected = connection(server, manager)
        try await connected.connect()
        connected.disconnect()

        #expect(presenter.presentCount == 0)
        let refresh = try #require(backend.state.withLock { $0.tokenRequests.first })
        #expect(refresh["grant_type"] == "refresh_token")
        #expect(refresh["resource"] == backend.endpoint.absoluteString)
        #expect(store.tokens(for: server.id)?.accessToken != "expired-token")
    }

    @Test(.timeLimit(.minutes(1)))
    func revokedAccessToken_401IsAnsweredByRefresh() async throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, _) = makeManager(backend, store: store)
        let server = makeServer(backend.endpoint)
        backend.registerClient("existing-client")
        let issued = backend.issueTokens()
        store.setClient(
            .init(clientID: "existing-client", clientSecret: nil, tokenEndpointAuthMethod: "none",
                  source: .dynamic, issuer: backend.issuer.absoluteString, endpoint: backend.endpoint.absoluteString),
            for: server.id,
        )
        // Not expired locally, but unknown to the server.
        store.setTokens(
            .init(endpoint: backend.endpoint.absoluteString, resource: backend.endpoint.absoluteString,
                  issuer: backend.issuer.absoluteString, accessToken: "revoked-token", refreshToken: issued.refresh,
                  expiresAt: .now.addingTimeInterval(3600), scopes: [], clientID: "existing-client",
                  tokenEndpoint: "https://\(backend.authHost)/token"),
            for: server.id,
        )

        let connected = connection(server, manager)
        try await connected.connect()
        connected.disconnect()
        #expect(backend.count("/token") == 1)
        #expect(manager.state(for: server.id) != .signInRequired)
    }

    @Test(.timeLimit(.minutes(1)))
    func concurrentRefreshes_shareOneTokenRequest() async throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, _) = makeManager(backend, store: store)
        let serverID = UUID().uuidString
        backend.registerClient("existing-client")
        let issued = backend.issueTokens()
        store.setClient(
            .init(clientID: "existing-client", clientSecret: nil, tokenEndpointAuthMethod: "none",
                  source: .dynamic, issuer: backend.issuer.absoluteString, endpoint: backend.endpoint.absoluteString),
            for: serverID,
        )
        let stale = MCPOAuthTokenRecord(
            endpoint: backend.endpoint.absoluteString, resource: backend.endpoint.absoluteString,
            issuer: backend.issuer.absoluteString, accessToken: "stale", refreshToken: issued.refresh,
            expiresAt: .distantPast, scopes: [], clientID: "existing-client",
            tokenEndpoint: "https://\(backend.authHost)/token",
        )
        store.setTokens(stale, for: serverID)

        let endpoint = backend.endpoint
        let results = try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 5 {
                group.addTask {
                    try await manager.refreshTokens(serverID: serverID, endpoint: endpoint, replacing: stale).accessToken
                }
            }
            var tokens: Set<String> = []
            for try await token in group { tokens.insert(token) }
            return tokens
        }
        #expect(results.count == 1)
        #expect(backend.count("/token") == 1)
    }

    // MARK: - Manual Client

    @Test(.timeLimit(.minutes(1)))
    func noRegistration_requiresManualClientID() async throws {
        let backend = MCPOAuthTestServer(options: .init(registration: false))
        let (manager, presenter) = makeManager(backend)
        let server = makeServer(backend.endpoint)

        await #expect(throws: (any Error).self) {
            try await connection(server, manager).connect()
        }
        #expect(manager.state(for: server.id) == .clientIDRequired)

        await #expect(throws: MCPOAuthError.clientIDRequired) {
            try await manager.signIn(server: server)
        }
        #expect(presenter.presentCount == 0)

        backend.registerClient("typed-client")
        manager.setManualClient(server: server, clientID: " typed-client ", clientSecret: "s3cret")
        #expect(manager.state(for: server.id) == .signInRequired)
        try await manager.signIn(server: server)

        #expect(backend.count("/register") == 0)
        #expect(backend.state.withLock { $0.authorizeQueries.first?["client_id"] } == "typed-client")
        let basic = try #require(backend.state.withLock { $0.tokenBasicAuth.first })
        #expect(basic == "Basic " + Data("typed-client:s3cret".utf8).base64EncodedString())
        #expect(manager.state(for: server.id) == .signedIn)
    }

    @Test(.timeLimit(.minutes(1)))
    func serverWithoutPKCE_isRefused() async throws {
        let backend = MCPOAuthTestServer(options: .init(pkce: false))
        let (manager, presenter) = makeManager(backend)
        let server = makeServer(backend.endpoint)
        await #expect(throws: MCPOAuthError.pkceUnsupported) {
            try await manager.signIn(server: server)
        }
        #expect(presenter.presentCount == 0)
        #expect(backend.count("/register") == 0)
    }

    @Test(.timeLimit(.minutes(1)))
    func plain401WithoutMetadata_isReportedUnsupported() async throws {
        let backend = MCPOAuthTestServer(options: .init(advertiseOAuth: false))
        let (manager, _) = makeManager(backend)
        let server = makeServer(backend.endpoint)
        await #expect(throws: (any Error).self) {
            try await connection(server, manager).connect()
        }
        guard case .unsupported = manager.state(for: server.id) else {
            Issue.record("expected unsupported, got \(manager.state(for: server.id))")
            return
        }
    }

    // MARK: - Header Precedence

    @Test(.timeLimit(.minutes(1)))
    func manualAuthorizationHeader_skipsOAuth() async throws {
        let backend = MCPOAuthTestServer()
        let (manager, _) = makeManager(backend)
        let server = makeServer(backend.endpoint, header: #"{"authorization": "Bearer manual-secret"}"#)

        #expect(manager.makeAuthorizer(for: server) == nil)
        let connected = connection(server, manager)
        try await connected.connect()
        connected.disconnect()

        #expect(backend.state.withLock { $0.authorizationHeaders.first } == "Bearer manual-secret")
        #expect(backend.count("/.well-known/oauth-protected-resource/mcp") == 0)
        #expect(backend.count("/.well-known/oauth-authorization-server") == 0)
        await #expect(throws: MCPOAuthError.manualAuthorizationHeader) {
            try await manager.signIn(server: server)
        }
    }

    // MARK: - Storage

    @Test
    func tokensBoundToEndpoint_areNotSentElsewhere() throws {
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, _) = makeManager(backend, store: store)
        let server = makeServer(backend.endpoint)
        store.setTokens(
            .init(endpoint: "https://other.example.com/mcp", resource: "https://other.example.com/mcp",
                  issuer: nil, accessToken: "other", refreshToken: nil, expiresAt: nil, scopes: [], clientID: nil,
                  tokenEndpoint: nil),
            for: server.id,
        )
        let authorizer = try #require(manager.makeAuthorizer(for: server))
        #expect(authorizer.authorizationHeader(for: backend.endpoint) == nil)
        #expect(!manager.hasTokens(for: server))
    }

    @Test
    func keychainStore_isDeviceOnlyAndPerServer() throws {
        let store = MCPOAuthKeychainStore(service: "wiki.qaq.flow.mcp-oauth.tests.\(UUID().uuidString)")
        let first = UUID().uuidString
        let second = UUID().uuidString
        defer {
            store.removeAll(for: first)
            store.removeAll(for: second)
        }
        let record = MCPOAuthTokenRecord(
            endpoint: "https://a.example.com/mcp", resource: "https://a.example.com/mcp", issuer: nil,
            accessToken: "secret-a", refreshToken: "refresh-a", expiresAt: nil, scopes: [], clientID: "c",
            tokenEndpoint: nil,
        )
        store.setTokens(record, for: first)
        store.setClient(
            .init(clientID: "c", clientSecret: nil, tokenEndpointAuthMethod: "none", source: .manual,
                  issuer: nil, endpoint: "https://a.example.com/mcp"),
            for: first,
        )

        #expect(store.tokens(for: first) == record)
        #expect(store.tokens(for: second) == nil)
        #expect(store.storedServerIDs() == [first])

        let attributes = try #require(store.attributes(forTokensOf: first))
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String)
        let synchronizable = attributes[kSecAttrSynchronizable as String]
        #expect(synchronizable == nil || (synchronizable as? Bool) == false || (synchronizable as? NSNumber)?.boolValue == false)

        // Updating keeps one item.
        var updated = record
        updated.accessToken = "secret-b"
        store.setTokens(updated, for: first)
        #expect(store.tokens(for: first)?.accessToken == "secret-b")

        store.removeAll(for: first)
        #expect(store.tokens(for: first) == nil)
        #expect(store.client(for: first) == nil)
        #expect(store.storedServerIDs().isEmpty)
    }

    /// Signing in writes nothing into the server record, so neither the
    /// database, iCloud sync nor a .fdmcp export can carry it; removing the
    /// server deletes the Keychain items.
    @Test(.timeLimit(.minutes(1)))
    func signedInServer_exportCarriesNoSecretsAndRemoveDeletesThem() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let backend = MCPOAuthTestServer()
        let store = MCPOAuthMemoryStore()
        let (manager, _) = makeManager(backend, store: store)
        let service = MCPService.shared
        let originalOAuth = service.oauth
        service.oauth = manager
        defer { service.oauth = originalOAuth }

        let server = service.create { server in
            server.update(\.endpoint, to: backend.endpoint.absoluteString)
            server.update(\.isEnabled, to: false)
        }
        try await manager.signIn(server: try #require(service.server(with: server.id)))
        let tokens = try #require(store.tokens(for: server.id))
        let client = try #require(store.client(for: server.id))

        let after = try service.exportServerData(try #require(service.server(with: server.id)))
        let text = String(decoding: after, as: UTF8.self)
        #expect(!text.contains(tokens.accessToken))
        #expect(!text.contains(client.clientID))
        #expect(!text.contains("refresh-"))

        // Changing the endpoint drops tokens issued for the old one.
        service.edit(identifier: server.id) { $0.update(\.endpoint, to: backend.endpoint.absoluteString + "/v2") }
        #expect(store.tokens(for: server.id) == nil)

        store.setTokens(tokens, for: server.id)
        service.remove(server.id)
        #expect(store.tokens(for: server.id) == nil)
        #expect(store.client(for: server.id) == nil)
    }

    @Test(.timeLimit(.minutes(1)))
    func callbackWithWrongState_isRejected() async throws {
        let backend = MCPOAuthTestServer()
        final class ForgingPresenter: MCPOAuthPresenting, @unchecked Sendable {
            func present(authorizationURL _: URL, callbackScheme _: String) async throws -> URL {
                URL(string: "flowdown://mcp-oauth/callback?code=forged&state=wrong")!
            }
        }
        let store = MCPOAuthMemoryStore()
        let manager = MCPOAuthManager(
            store: store,
            presenter: ForgingPresenter(),
            configureSession: { MCPOAuthStubProtocol.configure($0) },
        )
        let server = makeServer(backend.endpoint)
        await #expect(throws: (any Error).self) {
            try await manager.signIn(server: server)
        }
        #expect(backend.count("/token") == 0)
        #expect(store.tokens(for: server.id) == nil)
    }
}

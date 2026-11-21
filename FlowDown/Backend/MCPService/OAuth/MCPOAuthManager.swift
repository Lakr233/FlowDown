//
//  MCPOAuthManager.swift
//  FlowDown
//

import AuthenticationServices
import Combine
import Foundation
import MCP
import os
import Storage
import UIKit

/// Shows the authorization page and returns the redirect it ends on.
protocol MCPOAuthPresenting: AnyObject, Sendable {
    func present(authorizationURL: URL, callbackScheme: String) async throws -> URL
}

/// Owns MCP sign-in for every server: the in-memory state each server's UI
/// shows, the Keychain-backed tokens and clients, and the only code paths
/// that register clients or show a browser. Connections only ever read
/// tokens, refresh them, and report that a sign-in is needed.
final class MCPOAuthManager: @unchecked Sendable {
    static let shared = MCPOAuthManager(
        store: MCPOAuthKeychainStore.shared,
        presenter: MCPOAuthWebPresenter(),
    )

    static let callbackScheme = "flowdown"
    static let callbackHost = "mcp-oauth"
    static let redirectURI = URL(string: "flowdown://mcp-oauth/callback")!

    let store: any MCPOAuthStoring
    let presenter: any MCPOAuthPresenting
    /// Applied to every URLSession built for OAuth and MCP traffic; tests
    /// install URLProtocol stubs here.
    let configureSession: @Sendable (URLSessionConfiguration) -> Void
    let http: MCPOAuthHTTPClient

    /// In-memory only; never written to the database.
    let states = CurrentValueSubject<[ModelContextServer.ID: MCPOAuthState], Never>([:])

    private struct Shared {
        var states: [ModelContextServer.ID: MCPOAuthState] = [:]
        var discoveries: [ModelContextServer.ID: MCPOAuthDiscovery] = [:]
        var challengeMetadataURLs: [ModelContextServer.ID: URL] = [:]
        var challengeScopes: [ModelContextServer.ID: String] = [:]
        var signInFlights: Set<ModelContextServer.ID> = []
        var refreshFlights: [ModelContextServer.ID: Task<MCPOAuthTokenRecord, Swift.Error>] = [:]
    }

    private let shared = OSAllocatedUnfairLock(initialState: Shared())

    init(
        store: any MCPOAuthStoring,
        presenter: any MCPOAuthPresenting,
        configureSession: @escaping @Sendable (URLSessionConfiguration) -> Void = { _ in },
    ) {
        self.store = store
        self.presenter = presenter
        self.configureSession = configureSession
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configureSession(configuration)
        http = MCPOAuthHTTPClient(session: URLSession(configuration: configuration))
    }

    // MARK: - State

    func state(for serverID: ModelContextServer.ID) -> MCPOAuthState {
        shared.withLock { $0.states[serverID] } ?? .none
    }

    func setState(_ state: MCPOAuthState, for serverID: ModelContextServer.ID) {
        let snapshot: [ModelContextServer.ID: MCPOAuthState]? = shared.withLock {
            guard $0.states[serverID] ?? .none != state else { return nil }
            $0.states[serverID] = state == .none ? nil : state
            return $0.states
        }
        if let snapshot { states.send(snapshot) }
    }

    /// Whether the server's own headers carry an `Authorization` value,
    /// which always wins over OAuth.
    static func hasManualAuthorization(_ server: ModelContextServer) -> Bool {
        guard let data = server.header.data(using: .utf8),
              let headers = try? JSONDecoder().decode([String: String].self, from: data)
        else { return false }
        return headers.contains { key, value in
            key.caseInsensitiveCompare("Authorization") == .orderedSame
                && !value.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    /// The authorizer for one connection, or nil when the server's headers
    /// already authorize it.
    func makeAuthorizer(for server: ModelContextServer) -> (any HTTPClientAuthorizer)? {
        guard !Self.hasManualAuthorization(server),
              let endpoint = URL(string: server.endpoint)
        else { return nil }
        return MCPOAuthAuthorizer(serverID: server.id, endpoint: endpoint, manager: self)
    }

    func hasTokens(for server: ModelContextServer) -> Bool {
        guard let endpoint = URL(string: server.endpoint) else { return false }
        return store.tokens(for: server.id)?.matches(endpoint: endpoint) == true
    }

    /// Client ID typed in by hand for this server, if any.
    func manualClient(for server: ModelContextServer) -> MCPOAuthClientRecord? {
        guard let record = store.client(for: server.id),
              record.source == .manual,
              record.endpoint == server.endpoint
        else { return nil }
        return record
    }

    /// Called once a connection initialized: the server accepted whatever
    /// FlowDown sent, so any pending sign-in prompt is resolved.
    func noteConnected(_ server: ModelContextServer) {
        if Self.hasManualAuthorization(server) {
            setState(.none, for: server.id)
        } else {
            setState(hasTokens(for: server) ? .signedIn : .none, for: server.id)
        }
    }

    // MARK: - Connection Side (never interactive)

    /// Returns a usable token record for the endpoint, refreshing it once per
    /// server no matter how many connections ask at the same time.
    func refreshTokens(
        serverID: ModelContextServer.ID,
        endpoint: URL,
        replacing stale: MCPOAuthTokenRecord,
    ) async throws -> MCPOAuthTokenRecord {
        let task: Task<MCPOAuthTokenRecord, Swift.Error> = shared.withLock { state in
            if let existing = state.refreshFlights[serverID] { return existing }
            let task = Task<MCPOAuthTokenRecord, Swift.Error> { [self] in
                defer { _ = shared.withLock { $0.refreshFlights.removeValue(forKey: serverID) } }
                // Someone else may have refreshed since the caller looked.
                if let current = store.tokens(for: serverID),
                   current.matches(endpoint: endpoint),
                   current.accessToken != stale.accessToken,
                   !current.isExpired()
                {
                    return current
                }
                guard let client = store.client(for: serverID),
                      client.endpoint == endpoint.absoluteString,
                      client.clientID == stale.clientID
                else {
                    throw MCPOAuthHTTPClient.TokenRejected(status: 400, message: "invalid_client")
                }
                let refreshed = try await http.refresh(stale, endpoint: endpoint, client: client)
                store.setTokens(refreshed, for: serverID)
                return refreshed
            }
            state.refreshFlights[serverID] = task
            return task
        }
        return try await task.value
    }

    /// Works out what the user has to do after a 401 that no stored token
    /// could answer. Discovery only: no registration, no UI.
    func assessChallenge(
        serverID: ModelContextServer.ID,
        endpoint: URL,
        headers: [String: String],
    ) async {
        let challenge = DefaultOAuthWWWAuthenticateParser().parseBearer(from: headers)
        shared.withLock {
            $0.challengeMetadataURLs[serverID] = challenge?.resourceMetadataURL
            $0.challengeScopes[serverID] = challenge?.scope
        }
        do {
            let discovery = try await http.discover(
                endpoint: endpoint,
                resourceMetadataURL: challenge?.resourceMetadataURL,
            )
            shared.withLock { $0.discoveries[serverID] = discovery }
            let hasClient = store.client(for: serverID)?.matches(endpoint: endpoint, issuer: discovery.issuer) == true
            setState(
                hasClient || discovery.registrationEndpoint != nil ? .signInRequired : .clientIDRequired,
                for: serverID,
            )
        } catch is CancellationError {
            return
        } catch {
            Logger.network.errorFile("mcp oauth discovery failed for \(serverID): \(error.localizedDescription)")
            setState(.unsupported(error.localizedDescription), for: serverID)
        }
    }

    // MARK: - Interactive Sign-In

    /// Discovers, registers when needed, shows the authorization page and
    /// stores the tokens. The only path that may present UI or register a
    /// client.
    func signIn(server: ModelContextServer) async throws {
        let serverID = server.id
        guard !Self.hasManualAuthorization(server) else {
            throw MCPOAuthError.manualAuthorizationHeader
        }
        guard let endpoint = URL(string: server.endpoint), MCPOAuthHTTPClient.isSecure(endpoint) else {
            throw MCPOAuthError.insecureEndpoint
        }
        let claimed = shared.withLock { $0.signInFlights.insert(serverID).inserted }
        guard claimed else { throw MCPOAuthError.signInInProgress }
        defer { _ = shared.withLock { $0.signInFlights.remove(serverID) } }

        let (metadataURL, challengedScope) = shared.withLock {
            ($0.challengeMetadataURLs[serverID], $0.challengeScopes[serverID])
        }
        let discovery: MCPOAuthDiscovery
        do {
            discovery = try await http.discover(endpoint: endpoint, resourceMetadataURL: metadataURL)
        } catch let error as MCPOAuthError {
            setState(.unsupported(error.localizedDescription), for: serverID)
            throw error
        }

        var client = store.client(for: serverID)
        if client?.matches(endpoint: endpoint, issuer: discovery.issuer) != true {
            client = nil
        }
        if client == nil {
            guard let registrationEndpoint = discovery.registrationEndpoint else {
                setState(.clientIDRequired, for: serverID)
                throw MCPOAuthError.clientIDRequired
            }
            let registered = try await http.register(
                at: registrationEndpoint,
                discovery: discovery,
                redirectURI: Self.redirectURI,
                clientName: "FlowDown",
            )
            store.setClient(registered, for: serverID)
            client = registered
        }
        guard let client else { throw MCPOAuthError.clientIDRequired }

        let verifier = PKCE.makeVerifier()
        let codeChallenge = try PKCE.makeChallenge(from: verifier)
        let state = PKCE.makeVerifier(length: 32)
        let scopeSelector = DefaultOAuthScopeSelector()
        let scopes = scopeSelector.selectScopes(
            challengeScope: challengedScope,
            scopesSupported: discovery.scopes,
        )
        let flow = OAuthAuthorizationCodeFlow()
        let authorizationURL = try flow.buildURL(
            authorizationEndpoint: discovery.authorizationEndpoint,
            resource: discovery.resource,
            redirectURI: Self.redirectURI,
            clientID: client.clientID,
            codeChallenge: codeChallenge,
            scopes: scopes,
            state: state,
            scopeSerializer: scopeSelector,
        )

        let callback = try await presenter.present(
            authorizationURL: authorizationURL,
            callbackScheme: Self.callbackScheme,
        )
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let error = items.first(where: { $0.name == "error" })?.value {
            // Only trust an error that carries our state.
            if items.first(where: { $0.name == "state" })?.value == state {
                let description = items.first(where: { $0.name == "error_description" })?.value
                throw MCPOAuthError.authorizationDenied(description ?? error)
            }
        }
        // RFC 9207: an issuer in the response must be the one we asked.
        if let iss = items.first(where: { $0.name == "iss" })?.value,
           iss.trimmingCharacters(in: ["/"]) != discovery.issuer.absoluteString.trimmingCharacters(in: ["/"])
        {
            throw MCPOAuthError.authorizationDenied("issuer mismatch")
        }
        let code = try flow.extractCode(
            from: callback,
            expectedRedirectURI: Self.redirectURI,
            expectedState: state,
        )

        let tokens: MCPOAuthTokenRecord
        do {
            tokens = try await http.exchangeCode(
                code,
                verifier: verifier,
                redirectURI: Self.redirectURI,
                discovery: discovery,
                client: client,
            )
        } catch let rejected as MCPOAuthHTTPClient.TokenRejected {
            if client.source == .dynamic, rejected.message.hasPrefix("invalid_client") {
                // The registration went stale; the next attempt registers anew.
                store.setClient(nil, for: serverID)
            }
            throw rejected
        }
        store.setTokens(tokens, for: serverID)
        shared.withLock { $0.discoveries[serverID] = discovery }
        setState(.signedIn, for: serverID)
    }

    /// Forgets the tokens. A hand-typed Client ID stays; a dynamic
    /// registration stays too, as the next sign-in can reuse it.
    func signOut(serverID: ModelContextServer.ID) {
        store.setTokens(nil, for: serverID)
        setState(.signInRequired, for: serverID)
    }

    /// Stores a Client ID typed in by hand, replacing any registration. An
    /// empty ID clears it. Tokens issued to another client go away.
    func setManualClient(
        server: ModelContextServer,
        clientID: String,
        clientSecret: String?,
    ) {
        let clientID = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = clientSecret?.trimmingCharacters(in: .whitespacesAndNewlines)
        store.setTokens(nil, for: server.id)
        if clientID.isEmpty {
            store.setClient(nil, for: server.id)
        } else {
            let hasSecret = !(secret ?? "").isEmpty
            store.setClient(
                MCPOAuthClientRecord(
                    clientID: clientID,
                    clientSecret: hasSecret ? secret : nil,
                    tokenEndpointAuthMethod: hasSecret ? "client_secret_basic" : "none",
                    source: .manual,
                    issuer: nil,
                    endpoint: server.endpoint,
                ),
                for: server.id,
            )
        }
        if state(for: server.id) == .clientIDRequired || state(for: server.id) == .signedIn {
            setState(clientID.isEmpty ? .clientIDRequired : .signInRequired, for: server.id)
        }
    }

    // MARK: - Cleanup

    func removeAll(for serverID: ModelContextServer.ID) {
        store.removeAll(for: serverID)
        shared.withLock {
            $0.discoveries[serverID] = nil
            $0.challengeMetadataURLs[serverID] = nil
            $0.challengeScopes[serverID] = nil
        }
        setState(.none, for: serverID)
    }

    /// Drops Keychain items of servers that no longer exist, e.g. deleted
    /// on another device.
    func purge(keeping serverIDs: Set<ModelContextServer.ID>) {
        for orphan in store.storedServerIDs().subtracting(serverIDs) {
            removeAll(for: orphan)
        }
    }
}

// MARK: - Authorizer

/// Per-connection bridge between the SDK transport and the manager. It
/// attaches stored tokens and refreshes them; when the server still says
/// 401 it records what the user must do and lets the request fail, so an
/// unattended connect never waits on a browser.
final class MCPOAuthAuthorizer: HTTPClientAuthorizer, @unchecked Sendable {
    let serverID: ModelContextServer.ID
    let endpoint: URL
    private let manager: MCPOAuthManager
    private let lastSentToken = OSAllocatedUnfairLock<String?>(initialState: nil)

    init(serverID: ModelContextServer.ID, endpoint: URL, manager: MCPOAuthManager) {
        self.serverID = serverID
        self.endpoint = endpoint
        self.manager = manager
    }

    var maxAuthorizationAttempts: Int { 2 }

    /// OAuth only engages once a server challenges, and servers without
    /// authorization may well be plain HTTP; sign-in checks HTTPS itself.
    func validateEndpointSecurity(for _: URL) throws {}

    private func currentTokens() -> MCPOAuthTokenRecord? {
        guard let record = manager.store.tokens(for: serverID),
              record.matches(endpoint: endpoint)
        else { return nil }
        return record
    }

    func authorizationHeader(for _: URL) -> String? {
        guard let record = currentTokens(), !record.isExpired() else { return nil }
        lastSentToken.withLock { $0 = record.accessToken }
        return "Bearer \(record.accessToken)"
    }

    func prepareAuthorization(for _: URL, session _: URLSession) async throws {
        guard let record = currentTokens(),
              record.refreshToken != nil,
              record.isExpired(skew: 60)
        else { return }
        // Failures fall through to the 401 path.
        _ = try? await manager.refreshTokens(serverID: serverID, endpoint: endpoint, replacing: record)
    }

    func handleChallenge(
        statusCode: Int,
        headers: [String: String],
        endpoint _: URL,
        operationKey _: String?,
        session _: URLSession,
    ) async throws -> Bool {
        guard statusCode == 401 else { return false }

        if let record = currentTokens() {
            let sent = lastSentToken.withLock { $0 }
            if sent != record.accessToken, !record.isExpired() {
                // Another connection refreshed in the meantime.
                return true
            }
            if record.refreshToken != nil {
                do {
                    _ = try await manager.refreshTokens(serverID: serverID, endpoint: endpoint, replacing: record)
                    return true
                } catch is MCPOAuthHTTPClient.TokenRejected {
                    manager.store.setTokens(nil, for: serverID)
                } catch {
                    // The authorization server is unreachable; the tokens
                    // may still be good later.
                    Logger.network.errorFile("mcp oauth refresh failed for \(serverID): \(error.localizedDescription)")
                    manager.setState(.signInRequired, for: serverID)
                    return false
                }
            } else {
                manager.store.setTokens(nil, for: serverID)
            }
        }

        await manager.assessChallenge(serverID: serverID, endpoint: endpoint, headers: headers)
        return false
    }
}

// MARK: - Web Presenter

/// Shows the authorization page in `ASWebAuthenticationSession` using the
/// shared browser session, so existing identity-provider logins are reused.
final class MCPOAuthWebPresenter: NSObject, MCPOAuthPresenting, ASWebAuthenticationPresentationContextProviding, @unchecked Sendable {
    func present(authorizationURL: URL, callbackScheme: String) async throws -> URL {
        let box = OSAllocatedUnfairLock<ASWebAuthenticationSession?>(initialState: nil)
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Swift.Error>) in
                Task { @MainActor in
                    let session = ASWebAuthenticationSession(
                        url: authorizationURL,
                        callbackURLScheme: callbackScheme,
                    ) { url, error in
                        // The system calls this exactly once.
                        if let url {
                            continuation.resume(returning: url)
                        } else if let error = error as? ASWebAuthenticationSessionError,
                                  error.code == .canceledLogin
                        {
                            continuation.resume(throwing: MCPOAuthError.cancelled)
                        } else {
                            continuation.resume(throwing: error ?? MCPOAuthError.cancelled)
                        }
                    }
                    session.presentationContextProvider = self
                    session.prefersEphemeralWebBrowserSession = false
                    box.withLock { $0 = session }
                    if !session.start() {
                        // start() failing never calls the handler.
                        box.withLock { $0 = nil }
                        continuation.resume(throwing: MCPOAuthError.cancelled)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor in box.withLock { $0 }?.cancel() }
        }
    }

    nonisolated func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let windows = scenes.flatMap(\.windows)
            if let window = windows.first(where: \.isKeyWindow) ?? windows.first {
                return window
            }
            if let scene = scenes.first {
                return ASPresentationAnchor(windowScene: scene)
            }
            return ASPresentationAnchor()
        }
    }
}

@testable import FlowDown
import CryptoKit
import Foundation
import os

/// A scripted MCP resource server plus OAuth authorization server, served
/// through URLProtocol so no socket is opened. Each instance owns its own
/// hosts; requests are routed by host.
final class MCPOAuthTestServer: @unchecked Sendable {
    struct Options {
        var registration = true
        var pkce = true
        /// Answer 401 on the MCP endpoint without any OAuth metadata.
        var advertiseOAuth = true
    }

    let resourceHost: String
    let authHost: String
    let options: Options

    var endpoint: URL { URL(string: "https://\(resourceHost)/mcp")! }
    var issuer: URL { URL(string: "https://\(authHost)")! }

    struct Issued {
        var clientID: String
        var challenge: String
        var redirectURI: String
        var resource: String
    }

    struct State {
        var requests: [String: Int] = [:]
        var authorizationHeaders: [String] = []
        var registeredClients: Set<String> = []
        var codes: [String: Issued] = [:]
        var accessTokens: Set<String> = []
        var refreshTokens: Set<String> = []
        var tokenRequests: [[String: String]] = []
        var tokenBasicAuth: [String] = []
        var authorizeQueries: [[String: String]] = []
        var counter = 0
    }

    let state = OSAllocatedUnfairLock(initialState: State())

    init(options: Options = .init()) {
        let tag = UUID().uuidString.prefix(8).lowercased()
        resourceHost = "mcp-\(tag).example.com"
        authHost = "auth-\(tag).example.com"
        self.options = options
        MCPOAuthStubProtocol.register(self, hosts: [resourceHost, authHost])
    }

    deinit {
        MCPOAuthStubProtocol.unregister(hosts: [resourceHost, authHost])
    }

    func count(_ path: String) -> Int {
        state.withLock { $0.requests[path, default: 0] }
    }

    /// Issues a token pair directly, as if a sign-in had happened earlier.
    func issueTokens() -> (access: String, refresh: String) {
        state.withLock {
            $0.counter += 1
            let access = "access-\($0.counter)"
            let refresh = "refresh-\($0.counter)"
            $0.accessTokens.insert(access)
            $0.refreshTokens.insert(refresh)
            return (access, refresh)
        }
    }

    func registerClient(_ clientID: String) {
        _ = state.withLock { $0.registeredClients.insert(clientID) }
    }

    // MARK: - Authorization Page

    /// What a browser would do with the authorization URL: approve and
    /// redirect with a code bound to the PKCE challenge.
    func approve(_ authorizationURL: URL) throws -> URL {
        let items = URLComponents(url: authorizationURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var query: [String: String] = [:]
        for item in items { query[item.name] = item.value ?? "" }
        state.withLock { $0.authorizeQueries.append(query) }
        guard authorizationURL.host == authHost,
              query["response_type"] == "code",
              query["code_challenge_method"] == "S256",
              let challenge = query["code_challenge"],
              let clientID = query["client_id"],
              let redirect = query["redirect_uri"],
              let resource = query["resource"],
              let stateValue = query["state"]
        else { throw URLError(.badURL) }
        let code = state.withLock {
            $0.counter += 1
            let code = "code-\($0.counter)"
            $0.codes[code] = Issued(clientID: clientID, challenge: challenge, redirectURI: redirect, resource: resource)
            return code
        }
        var components = URLComponents(string: redirect)!
        components.queryItems = [
            .init(name: "code", value: code),
            .init(name: "state", value: stateValue),
            .init(name: "iss", value: issuer.absoluteString),
        ]
        return components.url!
    }

    // MARK: - Routing

    func respond(to request: URLRequest, body: Data) -> (Int, [String: String], Data) {
        let url = request.url!
        let path = url.path
        state.withLock { $0.requests[path, default: 0] += 1 }

        if url.host == resourceHost {
            return resource(request, path: path, body: body)
        }
        return authorization(request, path: path, body: body)
    }

    private func json(_ object: Any, status: Int = 200, headers: [String: String] = [:]) -> (Int, [String: String], Data) {
        var headers = headers
        headers["Content-Type"] = "application/json"
        return (status, headers, try! JSONSerialization.data(withJSONObject: object))
    }

    private func resource(_ request: URLRequest, path: String, body: Data) -> (Int, [String: String], Data) {
        if path == "/.well-known/oauth-protected-resource/mcp" {
            guard options.advertiseOAuth else { return (404, [:], Data()) }
            return json([
                "resource": endpoint.absoluteString,
                "authorization_servers": [issuer.absoluteString],
                "scopes_supported": ["mcp:tools"],
            ])
        }
        if path.hasPrefix("/.well-known/") {
            return (404, [:], Data())
        }
        guard path == "/mcp" else { return (404, [:], Data()) }

        let authorization = request.value(forHTTPHeaderField: "Authorization") ?? ""
        state.withLock { $0.authorizationHeaders.append(authorization) }
        let token = authorization.hasPrefix("Bearer ") ? String(authorization.dropFirst(7)) : ""
        let accepted = token == "manual-secret" || state.withLock { $0.accessTokens.contains(token) }
        guard accepted else {
            var challenge = "Bearer"
            if options.advertiseOAuth {
                challenge += " resource_metadata=\"https://\(resourceHost)/.well-known/oauth-protected-resource/mcp\", scope=\"mcp:tools\""
            }
            return (401, ["WWW-Authenticate": challenge], Data())
        }

        if request.httpMethod == "GET" {
            // No server-initiated stream: stops the SDK's GET retry loop.
            return (405, [:], Data())
        }
        guard let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let method = message["method"] as? String
        else { return (400, [:], Data()) }
        guard let id = message["id"] else {
            return (202, [:], Data())
        }
        let result: [String: Any] = switch method {
        case "initialize":
            [
                "protocolVersion": (message["params"] as? [String: Any])?["protocolVersion"] ?? "2025-06-18",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "oauth-test", "version": "1.0"],
            ]
        case "tools/list":
            ["tools": [["name": "whoami", "inputSchema": ["type": "object"]]]]
        default:
            [:]
        }
        return json(
            ["jsonrpc": "2.0", "id": id, "result": result],
            headers: ["Mcp-Session-Id": "session-\(resourceHost)"],
        )
    }

    private func authorization(_ request: URLRequest, path: String, body: Data) -> (Int, [String: String], Data) {
        switch path {
        case "/.well-known/oauth-authorization-server":
            var metadata: [String: Any] = [
                "issuer": issuer.absoluteString,
                "authorization_endpoint": "https://\(authHost)/authorize",
                "token_endpoint": "https://\(authHost)/token",
                "response_types_supported": ["code"],
            ]
            if options.pkce { metadata["code_challenge_methods_supported"] = ["S256"] }
            if options.registration { metadata["registration_endpoint"] = "https://\(authHost)/register" }
            return json(metadata)
        case "/register":
            guard options.registration,
                  let registration = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
                  (registration["redirect_uris"] as? [String]) == ["flowdown://mcp-oauth/callback"]
            else { return json(["error": "invalid_client_metadata"], status: 400) }
            let clientID = state.withLock {
                $0.counter += 1
                let id = "dyn-client-\($0.counter)"
                $0.registeredClients.insert(id)
                return id
            }
            return json(["client_id": clientID, "token_endpoint_auth_method": "none"], status: 201)
        case "/token":
            return token(request, body: body)
        default:
            return (404, [:], Data())
        }
    }

    private func token(_ request: URLRequest, body: Data) -> (Int, [String: String], Data) {
        var form: [String: String] = [:]
        for pair in String(decoding: body, as: UTF8.self).split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1).map {
                String($0).removingPercentEncoding ?? String($0)
            }
            if parts.count == 2 { form[parts[0]] = parts[1] }
        }
        let basic = request.value(forHTTPHeaderField: "Authorization") ?? ""
        state.withLock {
            $0.tokenRequests.append(form)
            $0.tokenBasicAuth.append(basic)
        }
        var clientID = form["client_id"]
        if basic.hasPrefix("Basic "),
           let decoded = Data(base64Encoded: String(basic.dropFirst(6))).map({ String(decoding: $0, as: UTF8.self) })
        {
            clientID = decoded.split(separator: ":").first.map(String.init)
        }
        guard let clientID, state.withLock({ $0.registeredClients.contains(clientID) }) else {
            return json(["error": "invalid_client"], status: 401)
        }
        guard form["resource"] == endpoint.absoluteString else {
            return json(["error": "invalid_target"], status: 400)
        }

        switch form["grant_type"] {
        case "authorization_code":
            guard let code = form["code"],
                  let issued = state.withLock({ $0.codes.removeValue(forKey: code) }),
                  issued.clientID == clientID,
                  issued.redirectURI == form["redirect_uri"],
                  let verifier = form["code_verifier"],
                  Self.s256(verifier) == issued.challenge
            else { return json(["error": "invalid_grant"], status: 400) }
        case "refresh_token":
            guard let refresh = form["refresh_token"],
                  state.withLock({ $0.refreshTokens.remove(refresh) }) != nil
            else { return json(["error": "invalid_grant"], status: 400) }
        default:
            return json(["error": "unsupported_grant_type"], status: 400)
        }
        let (access, refresh) = issueTokens()
        return json([
            "access_token": access,
            "token_type": "Bearer",
            "expires_in": 3600,
            "refresh_token": refresh,
            "scope": "mcp:tools",
        ])
    }

    static func s256(_ verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

/// Routes requests for registered hosts to their test server.
final class MCPOAuthStubProtocol: URLProtocol, @unchecked Sendable {
    private static let servers = OSAllocatedUnfairLock(initialState: [String: MCPOAuthTestServer]())

    static func register(_ server: MCPOAuthTestServer, hosts: [String]) {
        servers.withLock { map in
            for host in hosts { map[host] = server }
        }
    }

    static func unregister(hosts: [String]) {
        servers.withLock { map in
            for host in hosts { map[host] = nil }
        }
    }

    static func configure(_ configuration: URLSessionConfiguration) {
        configuration.protocolClasses = [MCPOAuthStubProtocol.self] + (configuration.protocolClasses ?? [])
    }

    override class func canInit(with request: URLRequest) -> Bool {
        guard let host = request.url?.host else { return false }
        return servers.withLock { $0[host] != nil }
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let server = Self.servers.withLock({ $0[url.host ?? ""] })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        let (status, headers, data) = server.respond(to: request, body: Self.body(of: request))
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty { client?.urlProtocol(self, didLoad: data) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func body(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

/// Stands in for ASWebAuthenticationSession: hands the authorization URL to
/// the test server and returns its redirect.
final class MCPOAuthStubPresenter: MCPOAuthPresenting, @unchecked Sendable {
    let server: MCPOAuthTestServer
    private let presented = OSAllocatedUnfairLock(initialState: 0)
    var presentCount: Int { presented.withLock { $0 } }

    init(server: MCPOAuthTestServer) {
        self.server = server
    }

    func present(authorizationURL: URL, callbackScheme: String) async throws -> URL {
        presented.withLock { $0 += 1 }
        precondition(callbackScheme == "flowdown")
        return try server.approve(authorizationURL)
    }
}

//
//  MCPOAuthHTTPClient.swift
//  FlowDown
//

import Foundation
import MCP

/// The network half of MCP authorization: RFC 9728/8414 discovery, RFC 7591
/// dynamic registration and RFC 6749 token requests with RFC 8707 resource
/// indicators. The SDK keeps its versions of these internal, so FlowDown
/// carries its own; URL construction reuses the SDK's public helpers.
struct MCPOAuthHTTPClient {
    let session: URLSession
    private let discovery = DefaultOAuthMetadataDiscovery()

    init(session: URLSession) {
        self.session = session
    }

    // MARK: - Discovery

    func canonicalResource(for endpoint: URL) throws -> URL {
        do {
            return try discovery.canonicalResourceURI(from: endpoint)
        } catch {
            throw MCPOAuthError.insecureEndpoint
        }
    }

    func discover(endpoint: URL, resourceMetadataURL: URL? = nil) async throws -> MCPOAuthDiscovery {
        let canonical = try canonicalResource(for: endpoint)

        var candidates: [URL] = []
        if let resourceMetadataURL, Self.isSecure(resourceMetadataURL) {
            candidates.append(resourceMetadataURL)
        }
        candidates.append(contentsOf: discovery.protectedResourceMetadataURLs(for: endpoint))

        var resourceMetadata: MCPOAuthProtectedResourceMetadata?
        for url in candidates {
            if let metadata: MCPOAuthProtectedResourceMetadata = try await fetchJSON(url) {
                resourceMetadata = metadata
                break
            }
        }
        guard let resourceMetadata else {
            throw MCPOAuthError.discoveryFailed(String(localized: "no protected resource metadata"))
        }

        var resource = canonical
        if let advertised = resourceMetadata.resource, let advertisedURL = URL(string: advertised) {
            // A metadata document for some other resource must not redirect
            // our tokens there (RFC 9728 §3.3).
            guard discovery.protectedResourceMatches(resource: advertisedURL, endpoint: canonical) else {
                throw MCPOAuthError.discoveryFailed(String(localized: "metadata is for a different resource"))
            }
            resource = advertisedURL
        }

        guard let issuerString = resourceMetadata.authorizationServers?.first,
              let issuer = URL(string: issuerString),
              Self.isSecure(issuer)
        else {
            throw MCPOAuthError.discoveryFailed(String(localized: "no authorization server"))
        }

        var serverMetadata: MCPOAuthServerMetadata?
        for url in discovery.authorizationServerMetadataURLs(for: issuer) {
            if let metadata: MCPOAuthServerMetadata = try await fetchJSON(url) {
                serverMetadata = metadata
                break
            }
        }
        guard let serverMetadata else {
            throw MCPOAuthError.discoveryFailed(String(localized: "no authorization server metadata"))
        }
        if let advertisedIssuer = serverMetadata.issuer,
           Self.trimmed(advertisedIssuer) != Self.trimmed(issuer.absoluteString)
        {
            throw MCPOAuthError.discoveryFailed(String(localized: "issuer mismatch"))
        }
        guard let authorizationEndpoint = serverMetadata.authorizationEndpoint.flatMap(URL.init(string:)),
              let tokenEndpoint = serverMetadata.tokenEndpoint.flatMap(URL.init(string:)),
              Self.isSecure(authorizationEndpoint), Self.isSecure(tokenEndpoint)
        else {
            throw MCPOAuthError.discoveryFailed(String(localized: "missing or insecure endpoints"))
        }
        // MCP requires S256 and requires refusing servers that do not say so.
        guard serverMetadata.codeChallengeMethodsSupported?.contains("S256") == true else {
            throw MCPOAuthError.pkceUnsupported
        }
        let registrationEndpoint = serverMetadata.registrationEndpoint
            .flatMap(URL.init(string:))
            .flatMap { Self.isSecure($0) ? $0 : nil }

        return MCPOAuthDiscovery(
            endpoint: endpoint,
            resource: resource,
            issuer: issuer,
            authorizationEndpoint: authorizationEndpoint,
            tokenEndpoint: tokenEndpoint,
            registrationEndpoint: registrationEndpoint,
            scopes: resourceMetadata.scopesSupported,
        )
    }

    // MARK: - Dynamic Client Registration

    func register(
        at registrationEndpoint: URL,
        discovery: MCPOAuthDiscovery,
        redirectURI: URL,
        clientName: String,
    ) async throws -> MCPOAuthClientRecord {
        var request = URLRequest(url: registrationEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let body: [String: Any] = [
            "client_name": clientName,
            "redirect_uris": [redirectURI.absoluteString],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            throw MCPOAuthError.registrationFailed(Self.describeError(data, status: status))
        }
        struct Registration: Decodable {
            var client_id: String
            var client_secret: String?
            var token_endpoint_auth_method: String?
        }
        guard let registration = try? JSONDecoder().decode(Registration.self, from: data),
              !registration.client_id.isEmpty
        else {
            throw MCPOAuthError.registrationFailed(String(localized: "invalid response"))
        }
        let method = registration.token_endpoint_auth_method
            ?? (registration.client_secret == nil ? "none" : "client_secret_basic")
        return MCPOAuthClientRecord(
            clientID: registration.client_id,
            clientSecret: registration.client_secret,
            tokenEndpointAuthMethod: method,
            source: .dynamic,
            issuer: discovery.issuer.absoluteString,
            endpoint: discovery.endpoint.absoluteString,
        )
    }

    // MARK: - Token Endpoint

    func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: URL,
        discovery: MCPOAuthDiscovery,
        client: MCPOAuthClientRecord,
    ) async throws -> MCPOAuthTokenRecord {
        let response = try await tokenRequest(
            tokenEndpoint: discovery.tokenEndpoint,
            parameters: [
                "grant_type": "authorization_code",
                "code": code,
                "code_verifier": verifier,
                "redirect_uri": redirectURI.absoluteString,
                "resource": discovery.resource.absoluteString,
            ],
            client: client,
        )
        return makeRecord(
            response,
            endpoint: discovery.endpoint,
            resource: discovery.resource.absoluteString,
            issuer: discovery.issuer.absoluteString,
            tokenEndpoint: discovery.tokenEndpoint,
            clientID: client.clientID,
            previous: nil,
        )
    }

    func refresh(
        _ record: MCPOAuthTokenRecord,
        endpoint: URL,
        client: MCPOAuthClientRecord,
    ) async throws -> MCPOAuthTokenRecord {
        guard let refreshToken = record.refreshToken,
              let tokenEndpoint = record.tokenEndpoint.flatMap(URL.init(string:)),
              Self.isSecure(tokenEndpoint)
        else {
            throw MCPOAuthError.tokenRequestFailed(String(localized: "no refresh token"))
        }
        var parameters = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "resource": record.resource,
        ]
        if !record.scopes.isEmpty {
            parameters["scope"] = record.scopes.joined(separator: " ")
        }
        let response = try await tokenRequest(
            tokenEndpoint: tokenEndpoint,
            parameters: parameters,
            client: client,
        )
        return makeRecord(
            response,
            endpoint: endpoint,
            resource: record.resource,
            issuer: record.issuer,
            tokenEndpoint: tokenEndpoint,
            clientID: client.clientID,
            previous: record,
        )
    }

    /// Thrown by the token endpoint for a grant it rejected outright
    /// (`invalid_grant`, `invalid_client`, …), as opposed to a transport
    /// failure that may pass.
    struct TokenRejected: Swift.Error, LocalizedError {
        let status: Int
        let message: String

        var errorDescription: String? {
            MCPOAuthError.tokenRequestFailed(message).errorDescription
        }
    }

    private func tokenRequest(
        tokenEndpoint: URL,
        parameters: [String: String],
        client: MCPOAuthClientRecord,
    ) async throws -> MCPOAuthTokenResponse {
        var parameters = parameters
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        switch (client.tokenEndpointAuthMethod, client.clientSecret) {
        case let ("client_secret_post", secret?):
            parameters["client_id"] = client.clientID
            parameters["client_secret"] = secret
        case let (_, secret?) where client.tokenEndpointAuthMethod != "none":
            // RFC 6749 §2.3.1: both parts are form-encoded before Basic.
            let credentials = "\(Self.formEncode(client.clientID)):\(Self.formEncode(secret))"
            request.setValue(
                "Basic \(Data(credentials.utf8).base64EncodedString())",
                forHTTPHeaderField: "Authorization",
            )
        default:
            parameters["client_id"] = client.clientID
        }
        request.httpBody = Data(Self.formBody(parameters).utf8)

        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200 ..< 300).contains(status) else {
            let message = Self.describeError(data, status: status)
            if (400 ..< 500).contains(status) {
                throw TokenRejected(status: status, message: message)
            }
            throw MCPOAuthError.tokenRequestFailed(message)
        }
        guard let token = try? JSONDecoder().decode(MCPOAuthTokenResponse.self, from: data),
              !token.accessToken.isEmpty
        else {
            throw MCPOAuthError.tokenRequestFailed(String(localized: "invalid response"))
        }
        if let type = token.tokenType, type.lowercased() != "bearer" {
            throw MCPOAuthError.tokenRequestFailed(String(localized: "unsupported token type \(type)"))
        }
        return token
    }

    private func makeRecord(
        _ response: MCPOAuthTokenResponse,
        endpoint: URL,
        resource: String,
        issuer: String?,
        tokenEndpoint: URL,
        clientID: String,
        previous: MCPOAuthTokenRecord?,
    ) -> MCPOAuthTokenRecord {
        MCPOAuthTokenRecord(
            endpoint: endpoint.absoluteString,
            resource: resource,
            issuer: issuer,
            accessToken: response.accessToken,
            // A refresh response may omit the refresh token, which means the
            // old one stays valid (RFC 6749 §6).
            refreshToken: response.refreshToken ?? previous?.refreshToken,
            expiresAt: response.expiresIn.map { Date.now.addingTimeInterval($0) },
            scopes: response.scope.map { $0.split(separator: " ").map(String.init) } ?? previous?.scopes ?? [],
            clientID: clientID,
            tokenEndpoint: tokenEndpoint.absoluteString,
        )
    }

    // MARK: - Helpers

    private func fetchJSON<T: Decodable>(_ url: URL) async throws -> T? {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            return nil
        }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// HTTPS, or plain HTTP to a loopback host for local development.
    static func isSecure(_ url: URL) -> Bool {
        switch url.scheme?.lowercased() {
        case "https":
            return url.host?.isEmpty == false
        case "http":
            let host = url.host?.lowercased() ?? ""
            return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
        default:
            return false
        }
    }

    private static func trimmed(_ string: String) -> String {
        string.hasSuffix("/") ? String(string.dropLast()) : string
    }

    private static let formAllowed: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()

    static func formEncode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: formAllowed) ?? string
    }

    static func formBody(_ parameters: [String: String]) -> String {
        parameters
            .sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")
    }

    static func describeError(_ data: Data, status: Int) -> String {
        struct ErrorBody: Decodable {
            var error: String?
            var error_description: String?
        }
        if let body = try? JSONDecoder().decode(ErrorBody.self, from: data), let error = body.error {
            if let description = body.error_description, !description.isEmpty {
                return "\(error): \(description)"
            }
            return error
        }
        return "HTTP \(status)"
    }
}

//
//  MCPOAuthModels.swift
//  FlowDown
//

import Foundation

/// What FlowDown knows about a server's sign-in, kept in memory only. It is
/// recomputed from the Keychain and the server's next 401 after a relaunch.
enum MCPOAuthState: Equatable {
    /// Nothing known: the server never asked for authorization, or it has a
    /// manual `Authorization` header.
    case none
    /// The server asked for authorization; signing in can proceed with a
    /// registered or dynamically registrable client.
    case signInRequired
    /// The server asked for authorization, but its authorization server
    /// offers no dynamic registration and no Client ID was entered.
    case clientIDRequired
    /// Tokens are stored for the current endpoint.
    case signedIn
    /// The server asked for authorization but does not advertise OAuth the
    /// way MCP requires; only a manual header can help.
    case unsupported(String)

    var needsSignIn: Bool {
        switch self {
        case .signInRequired, .clientIDRequired: true
        default: false
        }
    }
}

enum MCPOAuthError: Swift.Error, LocalizedError, Equatable {
    case insecureEndpoint
    case discoveryFailed(String)
    case pkceUnsupported
    case clientIDRequired
    case registrationFailed(String)
    case authorizationDenied(String)
    case cancelled
    case tokenRequestFailed(String)
    case signInInProgress
    case manualAuthorizationHeader

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            String(localized: "Sign-in requires an HTTPS endpoint.")
        case let .discoveryFailed(reason):
            String(localized: "This server does not advertise OAuth sign-in: \(reason)")
        case .pkceUnsupported:
            String(localized: "The authorization server does not support PKCE (S256), so FlowDown cannot sign in safely.")
        case .clientIDRequired:
            String(localized: "The authorization server does not support automatic registration. Enter a Client ID to sign in.")
        case let .registrationFailed(reason):
            String(localized: "Client registration failed: \(reason)")
        case let .authorizationDenied(reason):
            String(localized: "Authorization was denied: \(reason)")
        case .cancelled:
            String(localized: "Sign-in was cancelled.")
        case let .tokenRequestFailed(reason):
            String(localized: "Token request failed: \(reason)")
        case .signInInProgress:
            String(localized: "A sign-in for this server is already in progress.")
        case .manualAuthorizationHeader:
            String(localized: "This server uses an Authorization header from its configuration. Remove the header to sign in with OAuth.")
        }
    }
}

/// The slice of RFC 9728 protected resource metadata FlowDown needs.
struct MCPOAuthProtectedResourceMetadata: Decodable, Equatable {
    var resource: String?
    var authorizationServers: [String]?
    var scopesSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case resource
        case authorizationServers = "authorization_servers"
        case scopesSupported = "scopes_supported"
    }
}

/// The slice of RFC 8414 authorization server metadata FlowDown needs.
struct MCPOAuthServerMetadata: Decodable, Equatable {
    var issuer: String?
    var authorizationEndpoint: String?
    var tokenEndpoint: String?
    var registrationEndpoint: String?
    var codeChallengeMethodsSupported: [String]?
    var scopesSupported: [String]?
    var tokenEndpointAuthMethodsSupported: [String]?

    enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case registrationEndpoint = "registration_endpoint"
        case codeChallengeMethodsSupported = "code_challenge_methods_supported"
        case scopesSupported = "scopes_supported"
        case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
    }
}

/// Everything discovery found for one endpoint.
struct MCPOAuthDiscovery: Equatable {
    var endpoint: URL
    /// RFC 8707 resource indicator sent with every authorization and token
    /// request.
    var resource: URL
    var issuer: URL
    var authorizationEndpoint: URL
    var tokenEndpoint: URL
    var registrationEndpoint: URL?
    var scopes: [String]?
}

struct MCPOAuthTokenResponse: Decodable {
    var accessToken: String
    var tokenType: String?
    var expiresIn: Double?
    var refreshToken: String?
    var scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
    }
}

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
    case keychainUnavailable

    var errorDescription: String? {
        switch self {
        case .insecureEndpoint:
            String(localized: "Signing in needs a server address that starts with https://.")
        case let .discoveryFailed(reason):
            String(localized: "This server doesn't support sign-in. Details: \(reason)")
        case .pkceUnsupported:
            String(localized: "This server doesn't support the secure sign-in method FlowDown requires (PKCE S256), so FlowDown can't sign in.")
        case .clientIDRequired:
            String(localized: "This server can't set up sign-in for FlowDown on its own. Enter a Client ID, then sign in.")
        case let .registrationFailed(reason):
            String(localized: "FlowDown couldn't register with this server. Details: \(reason)")
        case let .authorizationDenied(reason):
            String(localized: "Sign-in was denied. Details: \(reason)")
        case .cancelled:
            String(localized: "Sign-in was canceled.")
        case let .tokenRequestFailed(reason):
            String(localized: "FlowDown couldn't finish signing in. Details: \(reason)")
        case .signInInProgress:
            String(localized: "Sign-in for this server is already in progress.")
        case .manualAuthorizationHeader:
            String(localized: "This server uses the Authorization field above. To sign in instead, clear that field.")
        case .keychainUnavailable:
            String(localized: "FlowDown couldn't save your sign-in to this device's Keychain, so you'd have to sign in again on every connection. Try again later.")
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

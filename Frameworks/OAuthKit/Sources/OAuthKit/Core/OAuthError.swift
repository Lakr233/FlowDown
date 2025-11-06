import Foundation

public enum OAuthError: Error, LocalizedError {
    case invalidConfiguration
    case invalidAuthorizationURL
    case invalidRedirectURI
    case invalidClientCredentials
    case invalidAuthorizationCode
    case invalidAccessToken
    case invalidRefreshToken
    case tokenExpired
    case networkError(Error)
    case serverError(String)
    case unknownError
    case pkceError(PKCEError)
    case stateValidationFailed
    case sessionExpired

    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            "Invalid OAuth configuration"
        case .invalidAuthorizationURL:
            "Invalid authorization URL"
        case .invalidRedirectURI:
            "Invalid redirect URI"
        case .invalidClientCredentials:
            "Invalid client credentials"
        case .invalidAuthorizationCode:
            "Invalid authorization code"
        case .invalidAccessToken:
            "Invalid access token"
        case .invalidRefreshToken:
            "Invalid refresh token"
        case .tokenExpired:
            "Token has expired"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        case let .serverError(message):
            "Server error: \(message)"
        case .unknownError:
            "Unknown error occurred"
        case let .pkceError(pkceError):
            "PKCE error: \(pkceError)"
        case .stateValidationFailed:
            "State validation failed"
        case .sessionExpired:
            "OAuth session has expired"
        }
    }
}

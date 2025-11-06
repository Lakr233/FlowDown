import Foundation

public struct OAuthConfiguration {
    public let clientId: String
    public let clientSecret: String?
    public let authorizationEndpoint: URL
    public let tokenEndpoint: URL
    public let redirectURI: URL
    public let scope: String?
    public let additionalParameters: [String: String]
    public let usePKCE: Bool
    public let pkceMethod: PKCECodeChallenge.Method
    public let httpHeaders: [String: String]

    public init(
        clientId: String,
        clientSecret: String? = nil,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        redirectURI: URL,
        scope: String? = nil,
        additionalParameters: [String: String] = [:],
        usePKCE: Bool = true,
        pkceMethod: PKCECodeChallenge.Method = .sha256,
        httpHeaders: [String: String] = Self.defaultHTTPHeaders
    ) {
        self.clientId = clientId
        self.clientSecret = clientSecret
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.redirectURI = redirectURI
        self.scope = scope
        self.additionalParameters = additionalParameters
        self.usePKCE = usePKCE
        self.pkceMethod = pkceMethod
        self.httpHeaders = httpHeaders
    }

    public static var defaultHTTPHeaders: [String: String] {
        [
            "Content-Type": "application/json",
            "Accept": "application/json",
        ]
    }

    public var isValid: Bool {
        !clientId.isEmpty &&
            authorizationEndpoint.scheme != nil &&
            tokenEndpoint.scheme != nil &&
            redirectURI.scheme != nil
    }

    public static func google(
        clientId: String,
        clientSecret: String? = nil,
        redirectURI: URL,
        scope: String? = "openid profile email",
        httpHeaders: [String: String] = Self.defaultHTTPHeaders
    ) -> OAuthConfiguration {
        OAuthConfiguration(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationEndpoint: URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!,
            tokenEndpoint: URL(string: "https://oauth2.googleapis.com/token")!,
            redirectURI: redirectURI,
            scope: scope,
            httpHeaders: httpHeaders
        )
    }

    public static func github(
        clientId: String,
        clientSecret: String? = nil,
        redirectURI: URL,
        scope: String? = "user:email",
        httpHeaders: [String: String] = Self.defaultHTTPHeaders
    ) -> OAuthConfiguration {
        OAuthConfiguration(
            clientId: clientId,
            clientSecret: clientSecret,
            authorizationEndpoint: URL(string: "https://github.com/login/oauth/authorize")!,
            tokenEndpoint: URL(string: "https://github.com/login/oauth/access_token")!,
            redirectURI: redirectURI,
            scope: scope,
            usePKCE: false,
            httpHeaders: httpHeaders
        )
    }
}

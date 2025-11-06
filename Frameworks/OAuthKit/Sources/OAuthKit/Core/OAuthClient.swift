import Foundation

public class OAuthClient {
    public let configuration: OAuthConfiguration
    private let networkClient: OAuthNetworkClient
    private let tokenStorage: TokenStorage
    private var currentPKCESession: PKCESession?

    public init(
        configuration: OAuthConfiguration,
        tokenStorage: TokenStorage? = nil
    ) {
        self.configuration = configuration
        networkClient = OAuthNetworkClient(configuration: configuration)
        self.tokenStorage = tokenStorage ?? KeychainTokenStorage(clientId: configuration.clientId)
    }

    public func buildAuthorizationURL() throws -> URL {
        guard configuration.isValid else {
            throw OAuthError.invalidConfiguration
        }

        var urlBuilder = URLBuilder(baseURL: configuration.authorizationEndpoint)
        urlBuilder.addQueryItem(name: "code", value: "true")
        urlBuilder.addQueryItem(name: "client_id", value: configuration.clientId)
        urlBuilder.addQueryItem(name: "redirect_uri", value: configuration.redirectURI.absoluteString)
        urlBuilder.addQueryItem(name: "response_type", value: "code")

        if let scope = configuration.scope {
            urlBuilder.addQueryItem(name: "scope", value: scope)
        }

        if configuration.usePKCE {
            do {
                let session = try PKCESession(challengeMethod: configuration.pkceMethod)
                currentPKCESession = session

                urlBuilder.addQueryItem(name: "code_challenge", value: session.challenge.value)
                urlBuilder.addQueryItem(name: "code_challenge_method", value: session.challenge.method.rawValue)
                urlBuilder.addQueryItem(name: "state", value: session.state)
            } catch {
                throw OAuthError.pkceError(error as! PKCEError)
            }
        }

        for (key, value) in configuration.additionalParameters {
            urlBuilder.addQueryItem(name: key, value: value)
        }

        guard let url = urlBuilder.build() else {
            throw OAuthError.invalidAuthorizationURL
        }

        return url
    }

    public func exchangeCodeForToken(code: String, state: String? = nil) async throws -> OAuthToken {
        if configuration.usePKCE {
            guard let session = currentPKCESession else {
                throw OAuthError.sessionExpired
            }

            if session.isExpired {
                throw OAuthError.sessionExpired
            }

            if let state, !session.validateState(state) {
                throw OAuthError.stateValidationFailed
            }
        }

        // Clean the authorization code by removing URL fragments
        let cleanedCode = code.components(separatedBy: "#").first?.components(separatedBy: "&").first ?? code

        var parameters: [String: String] = [
            "grant_type": "authorization_code",
            "client_id": configuration.clientId,
            "code": cleanedCode,
            "redirect_uri": configuration.redirectURI.absoluteString,
        ]

        if let clientSecret = configuration.clientSecret {
            parameters["client_secret"] = clientSecret
        }

        if configuration.usePKCE, let session = currentPKCESession {
            parameters["code_verifier"] = session.verifier.value
            // Do not include `state` in token request unless explicitly required by provider.
        }

        let token = try await networkClient.requestToken(
            endpoint: configuration.tokenEndpoint,
            parameters: parameters
        )

        try await tokenStorage.store(token)
        currentPKCESession = nil

        return token
    }

    public func refreshToken() async throws -> OAuthToken {
        guard let currentToken = try await tokenStorage.retrieve(),
              let refreshToken = currentToken.refreshToken
        else {
            throw OAuthError.invalidRefreshToken
        }

        var parameters: [String: String] = [
            "grant_type": "refresh_token",
            "client_id": configuration.clientId,
            "refresh_token": refreshToken,
        ]

        if let clientSecret = configuration.clientSecret {
            parameters["client_secret"] = clientSecret
        }

        let newToken = try await networkClient.requestToken(
            endpoint: configuration.tokenEndpoint,
            parameters: parameters
        )

        try await tokenStorage.store(newToken)
        return newToken
    }

    public func getValidToken() async throws -> OAuthToken {
        guard let token = try await tokenStorage.retrieve() else {
            throw OAuthError.invalidAccessToken
        }

        if token.isExpired {
            return try await refreshToken()
        }

        return token
    }

    public func revokeToken() async throws {
        await tokenStorage.clear()
        currentPKCESession = nil
    }
}

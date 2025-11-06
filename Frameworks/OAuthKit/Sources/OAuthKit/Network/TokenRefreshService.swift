import Foundation

public class TokenRefreshService {
    private let client: OAuthClient
    private let refreshThreshold: TimeInterval
    private var refreshTask: Task<OAuthToken, Error>?

    public init(client: OAuthClient, refreshThreshold: TimeInterval = 300) {
        self.client = client
        self.refreshThreshold = refreshThreshold
    }

    public func getValidToken() async throws -> OAuthToken {
        let token = try await client.getValidToken()

        if shouldRefreshToken(token) {
            return try await refreshTokenIfNeeded()
        }

        return token
    }

    private func shouldRefreshToken(_ token: OAuthToken) -> Bool {
        guard let expirationDate = token.expirationDate else {
            return false
        }

        let timeUntilExpiration = expirationDate.timeIntervalSinceNow
        return timeUntilExpiration <= refreshThreshold
    }

    private func refreshTokenIfNeeded() async throws -> OAuthToken {
        if let existingTask = refreshTask {
            return try await existingTask.value
        }

        let task = Task<OAuthToken, Error> {
            defer { refreshTask = nil }
            return try await client.refreshToken()
        }

        refreshTask = task
        return try await task.value
    }

    public func makeAuthenticatedRequest(url: URL, method: String = "GET") async throws -> Data {
        let token = try await getValidToken()
        let networkClient = OAuthNetworkClient()
        return try await networkClient.makeAuthenticatedRequest(url: url, token: token, method: method)
    }
}

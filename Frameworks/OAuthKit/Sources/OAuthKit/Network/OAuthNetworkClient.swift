import Foundation

public class OAuthNetworkClient {
    private let session: URLSession
    private let configuration: OAuthConfiguration?

    public init(session: URLSession = .shared, configuration: OAuthConfiguration? = nil) {
        self.session = session
        self.configuration = configuration
    }

    public func requestToken(endpoint: URL, parameters: [String: String]) async throws -> OAuthToken {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"

        let headers = configuration?.httpHeaders ?? OAuthConfiguration.defaultHTTPHeaders
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: parameters, options: [])
            request.httpBody = jsonData

            // Log request details for debugging
            print("🔄 Making OAuth token request to: \(endpoint)")
            print("📦 Request parameters: \(parameters.mapValues { $0.count > 10 ? "\($0.prefix(10))..." : $0 })")
            print("📋 Request headers: \(request.allHTTPHeaderFields ?? [:])")

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.unknownError
            }

            print("📡 Response status: \(httpResponse.statusCode)")
            print("📋 Response headers: \(httpResponse.allHeaderFields)")

            guard 200 ... 299 ~= httpResponse.statusCode else {
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                print("❌ Server error response: \(errorMessage)")
                throw OAuthError.serverError(errorMessage)
            }

            let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
            print("✅ Token response received: \(responseString)")

            return try JSONDecoder().decode(OAuthToken.self, from: data)

        } catch let error as OAuthError {
            throw error
        } catch {
            print("❌ Network error: \(error)")
            throw OAuthError.networkError(error)
        }
    }

    public func makeAuthenticatedRequest(url: URL, token: OAuthToken, method: String = "GET") async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method

        let headers = configuration?.httpHeaders ?? OAuthConfiguration.defaultHTTPHeaders
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.setValue(token.authorizationHeader, forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw OAuthError.unknownError
            }

            guard 200 ... 299 ~= httpResponse.statusCode else {
                if httpResponse.statusCode == 401 {
                    throw OAuthError.tokenExpired
                }
                let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown server error"
                throw OAuthError.serverError(errorMessage)
            }

            return data

        } catch let error as OAuthError {
            throw error
        } catch {
            throw OAuthError.networkError(error)
        }
    }
}

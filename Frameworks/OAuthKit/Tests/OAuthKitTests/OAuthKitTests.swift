@testable import OAuthKit
import XCTest

final class OAuthKitTests: XCTestCase {
    func testOAuthConfiguration() {
        let config = OAuthConfiguration(
            clientId: "test-client-id",
            clientSecret: "test-client-secret",
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            redirectURI: URL(string: "app://oauth")!,
            scope: "read write"
        )

        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.clientId, "test-client-id")
        XCTAssertEqual(config.scope, "read write")
        XCTAssertTrue(config.usePKCE)
        XCTAssertEqual(config.pkceMethod, .sha256)
    }

    func testGoogleConfiguration() {
        let config = OAuthConfiguration.google(
            clientId: "google-client-id",
            redirectURI: URL(string: "app://oauth")!
        )

        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.clientId, "google-client-id")
        XCTAssertEqual(config.scope, "openid profile email")
        XCTAssertTrue(config.usePKCE)
        XCTAssertEqual(config.authorizationEndpoint.absoluteString, "https://accounts.google.com/o/oauth2/v2/auth")
    }

    func testGitHubConfiguration() {
        let config = OAuthConfiguration.github(
            clientId: "github-client-id",
            redirectURI: URL(string: "app://oauth")!
        )

        XCTAssertTrue(config.isValid)
        XCTAssertEqual(config.clientId, "github-client-id")
        XCTAssertEqual(config.scope, "user:email")
        XCTAssertFalse(config.usePKCE)
        XCTAssertEqual(config.authorizationEndpoint.absoluteString, "https://github.com/login/oauth/authorize")
    }

    func testOAuthToken() {
        let token = OAuthToken(
            accessToken: "access-token",
            tokenType: "Bearer",
            expiresIn: 3600,
            refreshToken: "refresh-token",
            scope: "read write"
        )

        XCTAssertEqual(token.accessToken, "access-token")
        XCTAssertEqual(token.tokenType, "Bearer")
        XCTAssertEqual(token.expiresIn, 3600)
        XCTAssertEqual(token.refreshToken, "refresh-token")
        XCTAssertEqual(token.scope, "read write")
        XCTAssertFalse(token.isExpired)
        XCTAssertEqual(token.authorizationHeader, "Bearer access-token")
        XCTAssertNotNil(token.expirationDate)
    }

    func testTokenExpiration() {
        let expiredToken = OAuthToken(
            accessToken: "access-token",
            expiresIn: -1
        )

        XCTAssertTrue(expiredToken.isExpired)

        let nonExpiringToken = OAuthToken(
            accessToken: "access-token"
        )

        XCTAssertFalse(nonExpiringToken.isExpired)
        XCTAssertNil(nonExpiringToken.expirationDate)
    }

    func testMemoryTokenStorage() async throws {
        let storage = MemoryTokenStorage()

        let token = OAuthToken(accessToken: "test-token")

        try await storage.store(token)
        let retrieved = try await storage.retrieve()

        XCTAssertEqual(retrieved?.accessToken, "test-token")

        await storage.clear()
        let afterClear = try await storage.retrieve()

        XCTAssertNil(afterClear)
    }

    func testURLBuilder() {
        let baseURL = URL(string: "https://example.com/auth")!
        var builder = URLBuilder(baseURL: baseURL)

        builder.addQueryItem(name: "client_id", value: "test-client")
        builder.addQueryItem(name: "response_type", value: "code")
        builder.addQueryItem(name: "scope", value: "read write")
        builder.addQueryItem(name: "empty", value: nil)
        builder.addQueryItem(name: "blank", value: "")

        let url = builder.build()

        XCTAssertNotNil(url)
        XCTAssertTrue(url!.absoluteString.contains("client_id=test-client"))
        XCTAssertTrue(url!.absoluteString.contains("response_type=code"))
        XCTAssertTrue(url!.absoluteString.contains("scope=read%20write"))
        XCTAssertFalse(url!.absoluteString.contains("empty="))
        XCTAssertFalse(url!.absoluteString.contains("blank="))
    }

    func testOAuthClientAuthorizationURL() throws {
        let config = OAuthConfiguration(
            clientId: "test-client",
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            redirectURI: URL(string: "app://oauth")!,
            scope: "read"
        )

        let client = OAuthClient(configuration: config, tokenStorage: MemoryTokenStorage())
        let url = try client.buildAuthorizationURL()

        XCTAssertTrue(url.absoluteString.contains("client_id=test-client"))
        XCTAssertTrue(url.absoluteString.contains("response_type=code"))
        XCTAssertTrue(url.absoluteString.contains("scope=read"))
        XCTAssertTrue(url.absoluteString.contains("code_challenge="))
        XCTAssertTrue(url.absoluteString.contains("code_challenge_method=S256"))
        XCTAssertTrue(url.absoluteString.contains("state="))
    }

    func testDataExtensions() {
        let testData = "hello world".data(using: .utf8)!
        let urlSafeBase64 = testData.urlSafeBase64EncodedString

        XCTAssertEqual(urlSafeBase64, "aGVsbG8gd29ybGQ")

        let decodedData = Data(urlSafeBase64Encoded: urlSafeBase64)
        XCTAssertEqual(decodedData, testData)

        let hexString = testData.hexString
        XCTAssertEqual(hexString, "68656c6c6f20776f726c64")
    }
}

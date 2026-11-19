import Foundation
import MCP
import Testing

/// `OAuthAccessToken.isExpired` compares with `Date >=` inside the MCP
/// package, which the app now resolves to its own definition (see
/// Date+BackDeployedComparison.swift) on systems that report 27.2 or later.
struct DateBackDeployedComparisonTests {
    private func token(expiringAt date: Date) -> OAuthAccessToken {
        OAuthAccessToken(
            value: "token",
            tokenType: "Bearer",
            expiresAt: date,
            scopes: [],
            authorizationServer: nil,
            refreshToken: nil,
        )
    }

    @Test
    func `MCP token expiry keeps greater-or-equal semantics`() {
        let expiry = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let token = token(expiringAt: expiry)
        #expect(token.isExpired(now: expiry, skewSeconds: 0))
        #expect(token.isExpired(now: expiry.addingTimeInterval(1), skewSeconds: 0))
        #expect(!token.isExpired(now: expiry.addingTimeInterval(-1), skewSeconds: 0))
        #expect(token.isExpired(now: expiry.addingTimeInterval(-30), skewSeconds: 30))
        #expect(!token.isExpired(now: expiry.addingTimeInterval(-31), skewSeconds: 30))
    }
}

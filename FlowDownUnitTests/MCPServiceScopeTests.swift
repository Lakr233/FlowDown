@testable import FlowDown
import Storage
import Testing

struct MCPServiceScopeTests {
    @Test
    func `mcp errors expose human readable descriptions`() {
        let cases: [MCPError] = [
            .connectionFailed,
            .invalidConfiguration,
        ]

        for error in cases {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test
    func `model context server display names prefer custom name then host then fallback`() {
        let namedServer = ModelContextServer(
            name: "Team Tools",
            endpoint: "https://example.com/mcp",
        )
        let hostOnlyServer = ModelContextServer(endpoint: "https://example.com/mcp")
        let invalidServer = ModelContextServer(endpoint: "not a valid url")

        #expect(namedServer.displayName == "Team Tools")
        #expect(namedServer.decoratedDisplayName == "Team Tools • @example.com")

        #expect(hostOnlyServer.displayName == "example.com")
        #expect(hostOnlyServer.decoratedDisplayName == "@example.com")

        #expect(!invalidServer.displayName.isEmpty)
        #expect(invalidServer.displayName == invalidServer.decoratedDisplayName)
    }
}

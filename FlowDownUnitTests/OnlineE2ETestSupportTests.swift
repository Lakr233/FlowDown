@testable import FlowDown
import Foundation
@testable import Storage
import Testing

struct OnlineE2ETestSupportTests {
    @Test
    func `response formats use chat completions by default`() {
        let environment = [
            OnlineE2ETestSupport.tokenEnvName: "test-token",
            OnlineE2ETestSupport.endpointEnvName: "https://example.com/v1/chat/completions",
        ]

        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .chatCompletions, in: environment) == "https://example.com/v1/chat/completions")
        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .responses, in: environment) == nil)
        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [.chatCompletions])
    }

    @Test
    func `explicit responses endpoint enables responses coverage`() {
        let environment = [
            OnlineE2ETestSupport.tokenEnvName: "test-token",
            OnlineE2ETestSupport.endpointEnvName: "https://example.com/v1/chat/completions",
            OnlineE2ETestSupport.responsesEndpointEnvName: "https://example.com/v1/responses",
        ]

        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .responses, in: environment) == "https://example.com/v1/responses")
        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [.chatCompletions, .responses])
    }

    @Test
    func `responses enable flag derives standard responses endpoint`() {
        let environment = [
            OnlineE2ETestSupport.tokenEnvName: "test-token",
            OnlineE2ETestSupport.endpointEnvName: "https://example.com/v1/chat/completions",
            OnlineE2ETestSupport.responsesEnableFlag: "1",
        ]

        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .responses, in: environment) == "https://example.com/v1/responses")
        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [.chatCompletions, .responses])
    }

    @Test
    func `execution flag disables online tests`() {
        let environment = [
            OnlineE2ETestSupport.enableFlag: "0",
            OnlineE2ETestSupport.tokenEnvName: "test-token",
            OnlineE2ETestSupport.endpointEnvName: "https://example.com/v1/chat/completions",
        ]

        #expect(OnlineE2ETestSupport.isExecutionEnabled(in: environment) == false)
    }
}

@testable import FlowDown
import Foundation
@testable import Storage
import Testing

struct OnlineE2ETestSupportTests {
    @Test
    func `response formats use local chat completions endpoint`() {
        let environment = [
            OnlineE2ETestSupport.enableFlag: "1",
            OnlineE2ETestSupport.endpointEnvName: "http://127.0.0.1:8765/v1/chat/completions",
        ]

        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .chatCompletions, in: environment) == "http://127.0.0.1:8765/v1/chat/completions")
        #expect(OnlineE2ETestSupport.runtimeEndpoint(for: .responses, in: environment) == nil)
        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [.chatCompletions])
    }

    @Test
    func `missing local endpoint disables online formats`() {
        let environment = [
            OnlineE2ETestSupport.enableFlag: "1",
        ]

        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [])
        #expect(OnlineE2ETestSupport.isEnabled(for: .chatCompletions, in: environment) == false)
    }

    @Test
    func `execution flag disables online tests`() {
        let environment = [
            OnlineE2ETestSupport.enableFlag: "0",
            OnlineE2ETestSupport.endpointEnvName: "http://127.0.0.1:8765/v1/chat/completions",
        ]

        #expect(OnlineE2ETestSupport.isExecutionEnabled(in: environment) == false)
        #expect(OnlineE2ETestSupport.responseFormats(in: environment) == [])
    }
}

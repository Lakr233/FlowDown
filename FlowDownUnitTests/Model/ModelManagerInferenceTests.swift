import ChatClientKit
@testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ModelManagerInferenceTests {
    @Test
    func `infer uses injected chat service factory for unknown model identifiers`() async throws {
        let manager = ModelManager.shared
        let originalFactory = manager.chatServiceFactory
        defer { manager.chatServiceFactory = originalFactory }

        let service = ChatServiceSpy(chatHandler: { body in
            #expect(body.messages.count == 1)
            return ChatResponse(
                reasoning: "",
                text: "Injected response",
                images: [],
                tools: [],
            )
        })
        manager.chatServiceFactory = { _, _ in service }

        let response = try await manager.infer(
            with: "unit-test-model",
            input: [.user(content: .text("Ping"))],
        )

        #expect(response.text == "Injected response")
        #expect(service.receivedBodies.count == 1)
    }

    @Test
    func `testLocalModel uses injected chat service factory when gpu is stubbed available`() async {
        let manager = ModelManager.shared
        let originalFactory = manager.chatServiceFactory
        let originalGPUProvider = manager.gpuSupportProvider
        defer {
            manager.chatServiceFactory = originalFactory
            manager.gpuSupportProvider = originalGPUProvider
        }

        let service = ChatServiceSpy(streamHandler: { _ in
            AnyAsyncSequence(
                AsyncStream { continuation in
                    continuation.yield(.text("YES"))
                    continuation.finish()
                },
            )
        })
        manager.chatServiceFactory = { _, _ in service }
        manager.gpuSupportProvider = { true }

        let model = LocalModel(
            id: "unit-local-model",
            model_identifier: "unit/local-model",
            downloaded: Date.distantPast,
            size: 1,
            capabilities: [],
        )

        let result = await withCheckedContinuation { continuation in
            manager.testLocalModel(model) { outcome in
                continuation.resume(returning: outcome)
            }
        }

        switch result {
        case .success:
            #expect(service.receivedBodies.count == 1)
        case .failure:
            Issue.record("Expected injected local model test to succeed")
        }
    }
}

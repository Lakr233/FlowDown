import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct InferenceIntentHandlerTests {
    @Test
    func `execute uses injected dependencies to return streamed text`() async throws {
        var dependencies = InferenceIntentHandler.Dependencies.live
        dependencies.resolveModelIdentifier = { _ in "shortcut-model" }
        dependencies.modelCapabilities = { _ in [] }
        dependencies.preparePrompt = { "System Prompt" }
        dependencies.enabledToolsProvider = { [] }
        dependencies.shouldExposeMemory = { _, _ in false }
        dependencies.proactiveMemoryContextProvider = { nil }
        dependencies.memoryWritingToolsProvider = { [] }
        dependencies.streamingInfer = { _, messages, tools, toolChoice in
            #expect(messages.count == 2)
            #expect(tools == nil)
            #expect(toolChoice == nil)
            return makeResponseStream([.text("shortcut response")])
        }
        dependencies.persistConversation = { _, _, _, _, _, _ in
            Issue.record("execute should not persist conversations in this test")
        }

        let response = try await InferenceIntentHandler.execute(
            model: nil,
            message: "Hello",
            image: nil,
            audio: nil,
            options: .init(allowsImages: false),
            dependencies: dependencies,
        )

        #expect(response == "shortcut response")
    }

    @Test
    func `execute falls back to tool call summary when model emits only tool requests`() async throws {
        let toolRequest = try JSONDecoder().decode(
            ToolRequest.self,
            from: Data(#"{"id":"tool-1","name":"memory_write","args":"{}"}"#.utf8),
        )

        var dependencies = InferenceIntentHandler.Dependencies.live
        dependencies.resolveModelIdentifier = { _ in "shortcut-model" }
        dependencies.modelCapabilities = { _ in [] }
        dependencies.preparePrompt = { "" }
        dependencies.enabledToolsProvider = { [] }
        dependencies.shouldExposeMemory = { _, _ in false }
        dependencies.proactiveMemoryContextProvider = { nil }
        dependencies.memoryWritingToolsProvider = { [] }
        dependencies.streamingInfer = { _, _, _, _ in
            makeResponseStream([.tool(toolRequest)])
        }

        let response = try await InferenceIntentHandler.execute(
            model: nil,
            message: "Hello",
            image: nil,
            audio: nil,
            options: .init(allowsImages: false),
            dependencies: dependencies,
        )

        #expect(!response.isEmpty)
        #expect(response.contains("1"))
    }
}

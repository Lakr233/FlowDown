@testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct MemoryStoreAndToolsTests {
    @Test
    @MainActor
    func `memory store async APIs return searchable memories and proactive context`() async throws {
        try await withCleanMemoryStore {
            let teaMemory = try await MemoryStore.shared.storeAsync(
                content: "User likes jasmine tea",
                conversationId: "conversation-a",
            )
            let travelMemory = try await MemoryStore.shared.storeAsync(
                content: "User plans a trip to Berlin",
                conversationId: "conversation-b",
            )

            let allMemories = try await MemoryStore.shared.getAllMemoriesAsync()
            let teaMatches = try await MemoryStore.shared.searchMemories(query: "jasmine")
            let limitedMemories = try await MemoryStore.shared.getMemoriesWithLimit(1)
            let proactiveContext = await MemoryStore.shared.formattedProactiveMemoryContext(for: .recent15)

            #expect(allMemories.map(\.id).contains(teaMemory.id))
            #expect(allMemories.map(\.id).contains(travelMemory.id))
            #expect(teaMatches.map(\.id) == [teaMemory.id])
            #expect(limitedMemories.count == 1)
            #expect(proactiveContext != nil)
            #expect(proactiveContext?.contains("User likes jasmine tea") == true)
            #expect(proactiveContext?.contains("User plans a trip to Berlin") == true)
        }
    }

    @Test
    @MainActor
    func `memory tools store list update recall and delete memories`() async throws {
        try await withCleanMemoryStore {
            let storeTool = MTStoreMemoryTool()
            let listTool = MTListMemoriesTool()
            let updateTool = MTUpdateMemoryTool()
            let recallTool = MTRecallMemoryTool()
            let deleteTool = MTDeleteMemoryTool()

            let storeOutput = try await run(storeTool, #"{"content":"User prefers detailed release notes"}"#)
            let storedMemory = try #require(try await MemoryStore.shared.getAllMemoriesAsync().first)

            let listOutput = try await run(listTool, #"{"limit":10}"#)
            let updateOutput = try await run(
                updateTool,
                #"{"memory_id":"\#(storedMemory.id)","new_content":"User prefers concise release notes"}"#,
            )
            let recallOutput = try await run(recallTool, "{}")
            let deleteOutput = try await run(deleteTool, #"{"memory_id":"\#(storedMemory.id)","reason":"outdated"}"#)
            let recallAfterDelete = try await run(recallTool, "{}")

            #expect(storeOutput.contains("User prefers detailed release notes"))
            #expect(listOutput.contains(storedMemory.id))
            #expect(listOutput.contains("User prefers detailed release notes"))
            #expect(updateOutput == "Memory updated successfully.")
            #expect(recallOutput.contains("User prefers concise release notes"))
            #expect(deleteOutput == "Memory deleted successfully. Reason: outdated")
            #expect(recallAfterDelete == "No memories stored yet.")
        }
    }
}

private extension MemoryStoreAndToolsTests {
    func run(_ tool: any ModelTool, _ arguments: String) async throws -> String {
        try await tool.execute(.init(json: arguments), context: .headless).text
    }

    @MainActor
    func withCleanMemoryStore(
        _ body: () async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        try await MemoryStore.shared.deleteAllMemoriesAsync()
        do {
            try await body()
            try await MemoryStore.shared.deleteAllMemoriesAsync()
        } catch {
            try? await MemoryStore.shared.deleteAllMemoriesAsync()
            throw error
        }
    }
}

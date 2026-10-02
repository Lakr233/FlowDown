@testable import FlowDown
import Foundation
import Storage
import Testing
import UIKit

@Suite(.serialized)
struct MemoryStoreAndToolsTests {
    @Test
    @MainActor
    func `memory store async APIs return searchable memories and proactive context`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
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
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        try await withCleanMemoryStore {
            let anchor = UIView()
            let storeTool = MTStoreMemoryTool()
            let listTool = MTListMemoriesTool()
            let updateTool = MTUpdateMemoryTool()
            let recallTool = MTRecallMemoryTool()
            let deleteTool = MTDeleteMemoryTool()

            let storeOutput = try await storeTool.execute(
                with: #"{"content":"User prefers detailed release notes"}"#,
                anchorTo: anchor,
            )
            let storedMemory = try await waitForSingleMemory()

            let listOutput = try await listTool.execute(
                with: #"{"limit":10}"#,
                anchorTo: anchor,
            )
            let updateOutput = try await updateTool.execute(
                with: #"{"memory_id":"\#(storedMemory.id)","new_content":"User prefers concise release notes"}"#,
                anchorTo: anchor,
            )
            let recallOutput = try await recallTool.execute(with: "{}", anchorTo: anchor)
            let deleteOutput = try await deleteTool.execute(
                with: #"{"memory_id":"\#(storedMemory.id)","reason":"outdated"}"#,
                anchorTo: anchor,
            )
            let recallAfterDelete = try await recallTool.execute(with: "{}", anchorTo: anchor)

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
    @MainActor
    func withCleanMemoryStore(
        _ body: () async throws -> Void,
    ) async throws {
        try await resetMemories()
        do {
            try await body()
            try await resetMemories()
        } catch {
            try? await resetMemories()
            throw error
        }
    }

    @MainActor
    func resetMemories() async throws {
        try await MemoryStore.shared.deleteAllMemoriesAsync()
    }

    @MainActor
    func waitForSingleMemory() async throws -> Memory {
        for _ in 0 ..< 50 {
            let memories = try await MemoryStore.shared.getAllMemoriesAsync()
            if let memory = memories.first {
                return memory
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        throw NSError(domain: "MemoryStoreAndToolsTests", code: 1)
    }
}

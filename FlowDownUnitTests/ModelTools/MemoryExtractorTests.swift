import ChatClientKit
@testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct MemoryExtractorTests {
    @Test
    @MainActor
    func `extractIfNeeded stores parsed facts from model output`() async throws {
        try await withMemoryExtractorEnvironment { manager, storeTool in
            storeTool.isEnabled = true

            let service = ChatServiceSpy(chatHandler: { _ in
                ChatResponse(
                    reasoning: "",
                    text: """
                    Here are the facts:
                    ["User likes jasmine tea", "  User prefers concise replies  "]
                    """,
                    images: [],
                    tools: [],
                )
            })
            manager.chatServiceFactory = { _, _ in service }
            let conversationId = UUID().uuidString

            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: conversationId,
                    entries: [
                        (.user, "I really like jasmine tea."),
                        (.assistant, "I can remember that."),
                        (.user, "Please keep replies concise."),
                    ],
                ),
                conversationId: conversationId,
                using: "unit-test-memory-extractor",
            )

            let memories = try await waitForMemories(count: 2)

            #expect(service.receivedBodies.count == 1)
            #expect(memories.count == 2)
            #expect(memories.contains { $0.content == "User likes jasmine tea" })
            #expect(memories.contains { $0.content == "User prefers concise replies" })
        }
    }

    @Test
    @MainActor
    func `extractIfNeeded skips when memory storage is disabled model is missing or history is too short`() async throws {
        try await withMemoryExtractorEnvironment { manager, storeTool in
            let service = ChatServiceSpy(chatHandler: { _ in
                ChatResponse(reasoning: "", text: #"["User likes coffee"]"#, images: [], tools: [])
            })
            manager.chatServiceFactory = { _, _ in service }

            storeTool.isEnabled = false
            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "Remember that I like coffee."),
                        (.assistant, "Noted."),
                        (.user, "Please keep that in mind."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: "unit-test-memory-extractor",
            )

            storeTool.isEnabled = true
            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "Remember that I like coffee."),
                        (.assistant, "Noted."),
                        (.user, "Please keep that in mind."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: nil,
            )

            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "Remember that I like coffee."),
                        (.assistant, "Noted."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: "unit-test-memory-extractor",
            )

            let memories = try await MemoryStore.shared.getAllMemoriesAsync()

            #expect(service.receivedBodies.isEmpty)
            #expect(memories.isEmpty)
        }
    }

    @Test
    @MainActor
    func `extractIfNeeded deduplicates facts against existing memories`() async throws {
        try await withMemoryExtractorEnvironment { manager, storeTool in
            storeTool.isEnabled = true
            _ = try await MemoryStore.shared.storeAsync(content: "User likes jasmine tea")

            let service = ChatServiceSpy(chatHandler: { _ in
                ChatResponse(
                    reasoning: "",
                    text: #"["User likes jasmine tea", "User plans a trip to Berlin"]"#,
                    images: [],
                    tools: [],
                )
            })
            manager.chatServiceFactory = { _, _ in service }

            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "I still like jasmine tea."),
                        (.assistant, "I'll keep that in mind."),
                        (.user, "I am also planning a trip to Berlin."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: "unit-test-memory-extractor",
            )

            let memories = try await waitForMemories(count: 2)
            let contents = memories.map(\.content)

            #expect(service.receivedBodies.count == 1)
            #expect(contents.count(where: { $0 == "User likes jasmine tea" }) == 1)
            #expect(contents.contains("User plans a trip to Berlin"))
        }
    }

    @Test
    @MainActor
    func `extractIfNeeded ignores invalid model output and extractor failures`() async throws {
        try await withMemoryExtractorEnvironment { manager, storeTool in
            storeTool.isEnabled = true

            let invalidOutputService = ChatServiceSpy(chatHandler: { _ in
                ChatResponse(
                    reasoning: "",
                    text: "No structured facts were found.",
                    images: [],
                    tools: [],
                )
            })
            manager.chatServiceFactory = { _, _ in invalidOutputService }

            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "I enjoy hiking on weekends."),
                        (.assistant, "Sounds good."),
                        (.user, "You can remember that."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: "unit-test-memory-extractor",
            )

            let memoriesAfterInvalidOutput = try await MemoryStore.shared.getAllMemoriesAsync()
            #expect(memoriesAfterInvalidOutput.isEmpty)

            let failingService = ChatServiceSpy(chatHandler: { _ in
                throw NSError(domain: "MemoryExtractorTests", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Simulated extraction failure",
                ])
            })
            manager.chatServiceFactory = { _, _ in failingService }

            await MemoryExtractor.shared.extractIfNeeded(
                from: makeMessages(
                    conversationId: UUID().uuidString,
                    entries: [
                        (.user, "I also use Swift daily."),
                        (.assistant, "Understood."),
                        (.user, "Please remember that too."),
                    ],
                ),
                conversationId: UUID().uuidString,
                using: "unit-test-memory-extractor",
            )

            #expect(invalidOutputService.receivedBodies.count == 1)
            #expect(failingService.receivedBodies.count == 1)
            let memoriesAfterFailure = try await MemoryStore.shared.getAllMemoriesAsync()
            #expect(memoriesAfterFailure.isEmpty)
        }
    }

    @Test
    @MainActor
    func `extractIfNeeded enforces a per conversation cooldown`() async throws {
        try await withMemoryExtractorEnvironment { manager, storeTool in
            storeTool.isEnabled = true

            let responses = SequentialResponseSource(responses: [
                #"["User likes jasmine tea"]"#,
                #"["User plans a trip to Tokyo"]"#,
            ])
            let service = ChatServiceSpy(chatHandler: { _ in
                await ChatResponse(
                    reasoning: "",
                    text: responses.next(),
                    images: [],
                    tools: [],
                )
            })
            manager.chatServiceFactory = { _, _ in service }

            let conversationId = UUID().uuidString
            let messages = makeMessages(
                conversationId: conversationId,
                entries: [
                    (.user, "I like jasmine tea."),
                    (.assistant, "I'll remember that."),
                    (.user, "Keep that in memory."),
                ],
            )

            await MemoryExtractor.shared.extractIfNeeded(
                from: messages,
                conversationId: conversationId,
                using: "unit-test-memory-extractor",
            )
            _ = try await waitForMemories(count: 1)

            await MemoryExtractor.shared.extractIfNeeded(
                from: messages,
                conversationId: conversationId,
                using: "unit-test-memory-extractor",
            )

            let memories = try await MemoryStore.shared.getAllMemoriesAsync()

            #expect(service.receivedBodies.count == 1)
            #expect(memories.count == 1)
            #expect(memories.first?.content == "User likes jasmine tea")
        }
    }
}

private extension MemoryExtractorTests {
    @MainActor
    func withMemoryExtractorEnvironment(
        _ body: @MainActor (ModelManager, MTStoreMemoryTool) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let manager = ModelManager.shared
        let originalFactory = manager.chatServiceFactory
        let storeTool = MTStoreMemoryTool()
        let originalStoreEnabled = storeTool.isEnabled
        defer {
            manager.chatServiceFactory = originalFactory
            storeTool.isEnabled = originalStoreEnabled
        }

        try await MemoryStore.shared.deleteAllMemoriesAsync()

        do {
            try await body(manager, storeTool)
            try await MemoryStore.shared.deleteAllMemoriesAsync()
        } catch {
            try? await MemoryStore.shared.deleteAllMemoriesAsync()
            throw error
        }
    }

    func makeMessages(
        conversationId: Conversation.ID,
        entries: [(Message.Role, String)],
    ) -> [Message] {
        let storage = try! Storage.db()
        return entries.map { role, content in
            storage.makeMessage(with: conversationId, skipSave: true) { message in
                message.update(\.role, to: role)
                message.update(\.document, to: content)
            }
        }
    }

    @MainActor
    func waitForMemories(
        count: Int,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(50),
    ) async throws -> [Memory] {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            let memories = try await MemoryStore.shared.getAllMemoriesAsync()
            if memories.count == count {
                return memories
            }
            try await Task.sleep(for: pollInterval)
        }

        throw NSError(
            domain: "MemoryExtractorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for memories."],
        )
    }
}

private actor SequentialResponseSource {
    private var responses: [String]

    init(responses: [String]) {
        self.responses = responses
    }

    func next() -> String {
        guard !responses.isEmpty else { return "[]" }
        return responses.removeFirst()
    }
}

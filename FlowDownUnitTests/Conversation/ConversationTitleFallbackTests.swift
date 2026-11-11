//
//  ConversationTitleFallbackTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationTitleFallbackTests {
    // MARK: - The title rule

    @Test
    func `fallback title keeps a short message as it is`() {
        #expect(ConversationFallbackTitle.make(from: "Plan a trip to Kyoto") == "Plan a trip to Kyoto")
    }

    @Test
    func `fallback title collapses whitespace and newlines`() {
        let title = ConversationFallbackTitle.make(from: "  Plan a\n\n  trip\tto \r\n  Kyoto \n")

        #expect(title == "Plan a trip to Kyoto")
    }

    @Test
    func `fallback title keeps the first 50 characters and appends an ellipsis`() throws {
        let text = "Plan a three-day trip to Kyoto in spring with temples, gardens and food"
        let title = try #require(ConversationFallbackTitle.make(from: text))

        #expect(title == "Plan a three-day trip to Kyoto in spring with temp…")
        #expect(title.count == ConversationFallbackTitle.lengthLimit + 1)
    }

    @Test
    func `fallback title of exactly 50 characters is not cut`() {
        let exact = String(repeating: "a", count: 50)
        let over = String(repeating: "a", count: 51)

        #expect(ConversationFallbackTitle.make(from: exact) == exact)
        #expect(ConversationFallbackTitle.make(from: over) == exact + "…")
    }

    @Test
    func `fallback title counts collapsed whitespace once`() {
        // 50 characters only once the runs of spaces collapse.
        let words = Array(repeating: "abcd", count: 10).joined(separator: "     ")
        let collapsed = Array(repeating: "abcd", count: 10).joined(separator: " ")
        #expect(collapsed.count == 49)

        #expect(ConversationFallbackTitle.make(from: words) == collapsed)
    }

    @Test
    func `fallback title drops a space the cut ends on`() {
        // Character 50 is the space before "tail".
        let text = String(repeating: "a", count: 49) + " tail"

        #expect(ConversationFallbackTitle.make(from: text) == String(repeating: "a", count: 49) + "…")
    }

    @Test
    func `fallback title counts emoji and CJK as one character each`() {
        let family = "👨‍👩‍👧‍👦"
        let flag = "🇯🇵"
        #expect(family.count == 1)

        #expect(
            ConversationFallbackTitle.make(from: String(repeating: family, count: 60))
                == String(repeating: family, count: 50) + "…",
        )
        #expect(
            ConversationFallbackTitle.make(from: String(repeating: flag, count: 50))
                == String(repeating: flag, count: 50),
        )
        let chinese = String(repeating: "京都旅行计划", count: 10)
        #expect(ConversationFallbackTitle.make(from: chinese) == String(chinese.prefix(50)) + "…")
        #expect(ConversationFallbackTitle.make(from: "東京の天気は？") == "東京の天気は？")
    }

    @Test
    func `fallback title is nil for blank text`() {
        #expect(ConversationFallbackTitle.make(from: "") == nil)
        #expect(ConversationFallbackTitle.make(from: " \n\t \r\n ") == nil)
    }

    @Test
    func `fallback limit is separate from the generated title limit`() {
        #expect(ConversationFallbackTitle.lengthLimit == 50)
        #expect(ConversationMetadataToolCall.titleLengthLimit == 32)
    }

    @Test
    func `default name is recognized in every language and when blank`() {
        #expect(ConversationFallbackTitle.isDefault(String(localized: "Conversation")))
        #expect(ConversationFallbackTitle.isDefault("Conversation"))
        #expect(ConversationFallbackTitle.isDefault("对话"))
        #expect(ConversationFallbackTitle.isDefault("Unterhaltung"))
        #expect(ConversationFallbackTitle.isDefault(""))
        #expect(ConversationFallbackTitle.isDefault("  "))
        #expect(!ConversationFallbackTitle.isDefault("My trip"))
    }

    @Test
    func `attachment caption is recognized`() {
        #expect(ConversationFallbackTitle.isAttachmentCaption(String(localized: "Attached \(3) Documents")))
        #expect(ConversationFallbackTitle.isAttachmentCaption("Attached 12 Documents"))
        #expect(!ConversationFallbackTitle.isAttachmentCaption("Attached many Documents"))
        #expect(!ConversationFallbackTitle.isAttachmentCaption("Attached  Documents"))
        #expect(!ConversationFallbackTitle.isAttachmentCaption("Plan a trip"))
    }

    // MARK: - When the title is written

    @Test
    @MainActor
    func `first send shows the first message until the generated title replaces it`() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        // Apple Intelligence reports tool support without a stored model; the
        // injected service answers both the reply and the metadata request.
        let modelID = AppleIntelligenceModel.shared.modelIdentifier
        try await withConversation(modelID: modelID) { id, session in
            let (reply, replyContinuation) = AsyncStream<ChatResponseChunk>.makeStream()
            let service = ChatServiceSpy(
                chatHandler: { _ in Self.metadataResponse(title: "Kyoto Spring Trip") },
                streamHandler: { _ in AnyAsyncSequence(reply) },
            )
            try await withChatService(service) {
                let finished = Flag()
                session.doInfere(
                    modelID: modelID,
                    inputObject: .init(text: "Plan a three-day trip\nto Kyoto in spring"),
                ) { finished.value = true }

                // While the reply is still streaming.
                try await waitUntil { Self.title(of: id) == "Plan a three-day trip to Kyoto in spring" }
                #expect(!finished.value)
                #expect(Self.conversation(id)?.shouldAutoRename == true)

                replyContinuation.yield(.text("Day one: Fushimi Inari."))
                replyContinuation.finish()
                try await waitUntil(timeout: .seconds(15)) { finished.value }

                let conversation = try #require(Self.conversation(id))
                #expect(conversation.title == "Kyoto Spring Trip")
                #expect(!conversation.icon.isEmpty)
                #expect(!conversation.shouldAutoRename)
            }
        }
    }

    @Test
    @MainActor
    func `first send sets the fallback when auto rename is off`() async throws {
        try await withConversation(
            modelID: "unit-test-model-without-tools",
            shouldAutoRename: false,
        ) { id, session in
            let service = ChatServiceSpy(streamHandler: { _ in
                AnyAsyncSequence(AsyncStream<ChatResponseChunk> { continuation in
                    continuation.yield(.text("Sure."))
                    continuation.finish()
                })
            })
            try await withChatService(service) {
                let finished = Flag()
                session.doInfere(
                    modelID: "unit-test-model-without-tools",
                    inputObject: .init(text: "Compare two rice cookers"),
                ) { finished.value = true }
                try await waitUntil(timeout: .seconds(15)) { finished.value }

                let conversation = try #require(Self.conversation(id))
                #expect(conversation.title == "Compare two rice cookers")
                #expect(!conversation.shouldAutoRename)
            }
        }
    }

    @Test
    @MainActor
    func `model without tool capability keeps the first user message as title`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Plan a three-day trip\nto Kyoto in spring with temples, gardens and food")
            }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Day one: Fushimi Inari.") }
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Add a day in Nara") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Day four: Nara Park.") }

            await session.updateTitleAndIcon()

            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "Plan a three-day trip to Kyoto in spring with temp…")
            #expect(conversation.icon.isEmpty)
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `failed generation on a tool model keeps the first user message`() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        // The injected service answers with no tool call, as a provider that
        // rejected or ignored the forced call would.
        let modelID = AppleIntelligenceModel.shared.modelIdentifier
        try await withConversation(modelID: modelID) { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Compare two rice cookers") }
            session.applyFallbackTitleIfNeeded()
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Here is a comparison.") }

            let service = ChatServiceSpy()
            try await withChatService(service) {
                await session.updateTitleAndIcon()
            }

            #expect(service.receivedBodies.count == 1)
            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "Compare two rice cookers")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `generated title replaces the fallback`() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let modelID = AppleIntelligenceModel.shared.modelIdentifier
        try await withConversation(modelID: modelID) { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Compare two rice cookers") }
            session.applyFallbackTitleIfNeeded()
            #expect(Self.title(of: id) == "Compare two rice cookers")
            #expect(Self.conversation(id)?.shouldAutoRename == true)
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Here is a comparison.") }

            let service = ChatServiceSpy(chatHandler: { _ in Self.metadataResponse(title: "Rice Cooker Comparison") })
            try await withChatService(service) {
                await session.updateTitleAndIcon()
            }

            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "Rice Cooker Comparison")
            #expect(!conversation.shouldAutoRename)

            // Later sends and opening the conversation leave it alone.
            session.applyFallbackTitleIfNeeded()
            #expect(Self.title(of: id) == "Rice Cooker Comparison")
        }
    }

    @Test
    @MainActor
    func `attachments only messages keep the default name until text arrives`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            let attachmentOnly = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: String(localized: "Attached \(1) Documents"))
            }
            session.addAttachments([Self.textAttachment()], to: attachmentOnly)
            let holder = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Received an image")
            }
            session.markAsAttachmentHolder(holder)
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "A note about cats.") }

            session.applyFallbackTitleIfNeeded()
            await session.updateTitleAndIcon()

            var conversation = try #require(Self.conversation(id))
            #expect(conversation.title == Self.defaultTitle)
            #expect(conversation.shouldAutoRename)

            session.appendNewMessage(role: .user) { $0.update(\.document, to: "What breed is it?") }
            session.applyFallbackTitleIfNeeded()
            #expect(Self.title(of: id) == "What breed is it?")

            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "A Maine Coon.") }
            await session.updateTitleAndIcon()

            conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "What breed is it?")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `conversation without user messages keeps the default name`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Welcome.") }

            session.applyFallbackTitleIfNeeded()
            await session.updateTitleAndIcon()

            #expect(Self.title(of: id) == Self.defaultTitle)
        }
    }

    @Test
    @MainActor
    func `conversation stuck on the default name takes the first message when opened`() async throws {
        // As left by earlier versions: auto-rename spent, title never written.
        try await withConversation(
            modelID: "unit-test-model-without-tools",
            shouldAutoRename: false,
        ) { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Explain\nmonads   simply") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "A monad is…") }
            session.save()

            session.applyFallbackTitleIfNeeded()

            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "Explain monads simply")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `user rename is never overwritten`() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        let modelID = AppleIntelligenceModel.shared.modelIdentifier
        try await withConversation(modelID: modelID) { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Plan a trip") }
            session.applyFallbackTitleIfNeeded()
            #expect(Self.title(of: id) == "Plan a trip")
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Sure.") }
            // The user renames while the title is being generated.
            ConversationManager.shared.editConversation(identifier: id) {
                $0.update(\.title, to: "My trip")
                $0.update(\.shouldAutoRename, to: false)
            }

            let service = ChatServiceSpy(chatHandler: { _ in Self.metadataResponse(title: "Trip Planning") })
            try await withChatService(service) {
                await session.updateTitleAndIcon()
            }
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Add a day") }
            session.applyFallbackTitleIfNeeded()

            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "My trip")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `user rename is kept when generation fails`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Plan a trip") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Sure.") }
            ConversationManager.shared.editConversation(identifier: id) {
                $0.update(\.title, to: "My trip")
                $0.update(\.shouldAutoRename, to: false)
            }

            await session.updateTitleAndIcon()

            #expect(Self.title(of: id) == "My trip")
        }
    }

    @Test
    @MainActor
    func `requested title turns auto rename off so the fallback leaves it`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Plan a trip") }
            session.applyFallbackTitleIfNeeded()

            ConversationManager.shared.applyMetadata(
                ConversationMetadata(title: "Trip Planning", icon: nil),
                to: id,
                isAutomatic: false,
            )
            session.applyFallbackTitleIfNeeded()

            let conversation = try #require(Self.conversation(id))
            #expect(conversation.title == "Trip Planning")
            #expect(!conversation.shouldAutoRename)
        }
    }

    // MARK: - Support

    private static var defaultTitle: String {
        String(localized: "Conversation")
    }

    private final class Flag: @unchecked Sendable {
        var value = false
    }

    private static func conversation(_ id: Conversation.ID) -> Conversation? {
        ConversationManager.shared.conversation(identifier: id)
    }

    private static func title(of id: Conversation.ID) -> String? {
        conversation(id)?.title
    }

    private static func metadataResponse(title: String) -> ChatResponse {
        ChatResponse(
            reasoning: "",
            text: "",
            images: [],
            tools: [ToolRequest(
                name: ConversationMetadataToolCall.name,
                args: #"{"title":"\#(title)","icon":"🗾"}"#,
            )],
        )
    }

    private static func textAttachment() -> RichEditorView.Object.Attachment {
        RichEditorView.Object.Attachment(
            type: .text,
            name: "notes.txt",
            previewImage: .init(),
            imageRepresentation: .init(),
            textRepresentation: "notes",
            storageSuffix: UUID().uuidString,
        )
    }

    @MainActor
    private func withConversation(
        modelID: ModelManager.ModelIdentifier,
        shouldAutoRename: Bool = true,
        _ body: @MainActor (Conversation.ID, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: Self.defaultTitle)
            conversation.update(\.modelId, to: modelID)
            conversation.update(\.shouldAutoRename, to: shouldAutoRename)
        }
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        session.models.chat = modelID

        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        try await body(conversation.id, session)
    }

    @MainActor
    private func withChatService(
        _ service: ChatServiceSpy,
        _ body: @MainActor () async throws -> Void,
    ) async throws {
        let manager = ModelManager.shared
        let originalFactory = manager.chatServiceFactory
        manager.chatServiceFactory = { _, _ in service }
        defer { manager.chatServiceFactory = originalFactory }
        try await body()
    }

    @MainActor
    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: pollInterval)
        }
        Issue.record("timed out waiting for condition")
        throw CancellationError()
    }
}

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
    @Test
    func `fallback title keeps a short message as it is`() {
        #expect(ConversationMetadataToolCall.fallbackTitle(from: "Plan a trip to Kyoto") == "Plan a trip to Kyoto")
    }

    @Test
    func `fallback title collapses whitespace and newlines`() {
        let title = ConversationMetadataToolCall.fallbackTitle(from: "  Plan a\n\n  trip\tto   Kyoto \n")

        #expect(title == "Plan a trip to Kyoto")
    }

    @Test
    func `fallback title cuts long text to the title limit with an ellipsis`() throws {
        let title = try #require(ConversationMetadataToolCall.fallbackTitle(
            from: "Plan a three-day trip to Kyoto in spring with temples and food",
        ))

        #expect(title == "Plan a three-day trip to Kyoto…")
        #expect(title.count <= ConversationMetadataToolCall.titleLengthLimit)
    }

    @Test
    func `fallback title of exactly the limit is not cut`() {
        let text = String(repeating: "a", count: ConversationMetadataToolCall.titleLengthLimit)

        #expect(ConversationMetadataToolCall.fallbackTitle(from: text) == text)
    }

    @Test
    func `fallback title is nil for blank text`() {
        #expect(ConversationMetadataToolCall.fallbackTitle(from: "") == nil)
        #expect(ConversationMetadataToolCall.fallbackTitle(from: " \n\t ") == nil)
    }

    @Test
    @MainActor
    func `model without tool capability gets the first user message as title`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Plan a three-day trip\nto Kyoto in spring")
            }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Day one: Fushimi Inari.") }
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Add a day in Nara") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Day four: Nara Park.") }

            await session.updateTitleAndIcon()

            let conversation = try #require(ConversationManager.shared.conversation(identifier: id))
            #expect(conversation.title == "Plan a three-day trip to Kyoto…")
            #expect(conversation.icon.isEmpty)
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `failed generation on a tool model falls back to the first user message`() async throws {
        guard #available(iOS 26.0, macCatalyst 26.0, *) else { return }
        // Apple Intelligence reports tool support without a stored model, and
        // the injected service answers with no tool call, as a provider that
        // rejected or ignored the forced call would.
        let modelID = AppleIntelligenceModel.shared.modelIdentifier
        try await withConversation(modelID: modelID) { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Compare two rice cookers") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Here is a comparison.") }

            let service = ChatServiceSpy()
            let manager = ModelManager.shared
            let originalFactory = manager.chatServiceFactory
            manager.chatServiceFactory = { _, _ in service }
            defer { manager.chatServiceFactory = originalFactory }

            await session.updateTitleAndIcon()

            #expect(service.receivedBodies.count == 1)
            let conversation = try #require(ConversationManager.shared.conversation(identifier: id))
            #expect(conversation.title == "Compare two rice cookers")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `attachments only conversation keeps auto rename on until text arrives`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "") }
            let holder = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Received an image")
            }
            session.markAsAttachmentHolder(holder)
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "A photo of a cat.") }

            await session.updateTitleAndIcon()

            var conversation = try #require(ConversationManager.shared.conversation(identifier: id))
            #expect(conversation.title == Self.originalTitle)
            #expect(conversation.shouldAutoRename)

            session.appendNewMessage(role: .user) { $0.update(\.document, to: "What breed is it?") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "A Maine Coon.") }

            await session.updateTitleAndIcon()

            conversation = try #require(ConversationManager.shared.conversation(identifier: id))
            #expect(conversation.title == "What breed is it?")
            #expect(!conversation.shouldAutoRename)
        }
    }

    @Test
    @MainActor
    func `automatic title never replaces a title the user set`() async throws {
        try await withConversation(modelID: "unit-test-model-without-tools") { id, session in
            session.appendNewMessage(role: .user) { $0.update(\.document, to: "Plan a trip") }
            session.appendNewMessage(role: .assistant) { $0.update(\.document, to: "Sure.") }
            // The user renames while the title is being worked out.
            ConversationManager.shared.editConversation(identifier: id) {
                $0.update(\.title, to: "My trip")
                $0.update(\.shouldAutoRename, to: false)
            }

            await session.updateTitleAndIcon()

            let conversation = try #require(ConversationManager.shared.conversation(identifier: id))
            #expect(conversation.title == "My trip")
        }
    }

    private static let originalTitle = "Title Fallback Tests"

    @MainActor
    private func withConversation(
        modelID: ModelManager.ModelIdentifier,
        _ body: @MainActor (Conversation.ID, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: Self.originalTitle)
            conversation.update(\.modelId, to: modelID)
            conversation.update(\.shouldAutoRename, to: true)
        }
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        session.models.chat = modelID

        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        try await body(conversation.id, session)
    }
}

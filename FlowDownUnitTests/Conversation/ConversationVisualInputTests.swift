//
//  ConversationVisualInputTests.swift
//  FlowDownUnitTests
//

import ChatClientKit
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

/// Auxiliary tasks run on the chat model, and images go straight to a vision
/// model or, for a model without vision, are held back with a hint.
@Suite(.serialized)
struct ConversationVisualInputTests {
    @Test
    func `auxiliary model always follows the chat model`() {
        let models = ConversationSession.Models()
        #expect(models.auxiliary == nil)

        models.chat = "chat-model-a"
        #expect(models.auxiliary == "chat-model-a")

        models.chat = "chat-model-b"
        #expect(models.auxiliary == "chat-model-b")
    }

    @Test
    @MainActor
    func `session auxiliary model is the conversation model even with a retired task model stored`() async throws {
        let retiredKey = "Model.Default.Auxiliary"
        let previous = UserDefaults.standard.object(forKey: retiredKey)
        defer { UserDefaults.standard.set(previous, forKey: retiredKey) }
        UserDefaults.standard.set(Data(#""retired-task-model""#.utf8), forKey: retiredKey)

        try await withTemporarySession(modelID: "conversation-model") { session in
            session.updateModels()
            #expect(session.models.chat == "conversation-model")
            #expect(session.models.auxiliary == "conversation-model")
        }
    }

    @Test
    func `only undescribed images need a vision model`() {
        let image = makeImageAttachment()
        var describedImage = makeImageAttachment()
        describedImage.textRepresentation = "A red square"
        let text = RichEditorView.Object.Attachment(
            type: .text,
            name: "notes.txt",
            previewImage: .init(),
            imageRepresentation: .init(),
            textRepresentation: "notes",
            storageSuffix: UUID().uuidString,
        )

        #expect(ConversationSession.hasImagesRequiringVisualInput([image], modelCapabilities: []))
        #expect(ConversationSession.hasImagesRequiringVisualInput([text, image], modelCapabilities: [.tool]))
        #expect(!ConversationSession.hasImagesRequiringVisualInput([image], modelCapabilities: [.visual]))
        #expect(!ConversationSession.hasImagesRequiringVisualInput([describedImage], modelCapabilities: []))
        #expect(!ConversationSession.hasImagesRequiringVisualInput([text], modelCapabilities: []))
    }

    @Test
    @MainActor
    func `vision model receives the image itself`() async throws {
        try await withTemporarySession { session in
            let messages = await session.makeMessageFromAttachments(
                [makeImageAttachment()],
                modelCapabilities: [.visual],
            )
            #expect(messages.count == 1)
            guard case let .user(content, _) = messages.first, case let .parts(parts) = content else {
                Issue.record("Expected a user message with content parts.")
                return
            }
            let imageURLs = parts.compactMap { part -> URL? in
                if case let .imageURL(url, _) = part { url } else { nil }
            }
            #expect(imageURLs.count == 1)
            #expect(imageURLs.first?.absoluteString.hasPrefix("data:image/png;base64,") == true)

            await session.noteImagesRequiringVisualInput(
                [makeImageAttachment()],
                modelCapabilities: [.visual],
            )
            #expect(!session.messages.contains { $0.role == .hint })
        }
    }

    @Test
    @MainActor
    func `model without vision gets no image and the conversation shows a hint`() async throws {
        try await withTemporarySession { session in
            let attachments = [makeImageAttachment()]
            let messages = await session.makeMessageFromAttachments(attachments, modelCapabilities: [])
            #expect(messages.isEmpty)

            await session.noteImagesRequiringVisualInput(attachments, modelCapabilities: [])
            let hints = session.messages.filter { $0.role == .hint }
            #expect(hints.count == 1)
            #expect(hints.first?.document == ConversationSession.visualInputUnsupportedHintText)
            #expect(!session.messages.contains { $0.role == .assistant })
        }
    }
}

private extension ConversationVisualInputTests {
    func makeImageAttachment() -> RichEditorView.Object.Attachment {
        let data = ModelManager.testImage.pngData() ?? Data()
        return .init(
            type: .image,
            name: "square.png",
            previewImage: data,
            imageRepresentation: data,
            textRepresentation: "",
            storageSuffix: UUID().uuidString,
        )
    }

    @MainActor
    func withTemporarySession(
        modelID: String = "",
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Visual Input Tests \(UUID().uuidString.prefix(8))")
            conversation.update(\.modelId, to: modelID)
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        try await body(session)
    }
}

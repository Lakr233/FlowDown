//
//  ConversationInterruptedReasoningTests.swift
//  FlowDownUnitTests
//

@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationInterruptedReasoningTests {
    @Test
    @MainActor
    func interruptedReasoning_finalizesEmptyDocument() async throws {
        try await withTemporarySession { session in
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Hello")
            }
            let interrupted = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "abc")
            }

            session.finalizeInterruptedReasoning()

            #expect(interrupted.reasoningContent == "abc")
            #expect(interrupted.document == String(localized: "Thinking finished without output any content."))
        }
    }

    @Test
    @MainActor
    func interruptedReasoning_keepsOtherMessagesUntouched() async throws {
        try await withTemporarySession { session in
            let answered = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "abc")
                $0.update(\.document, to: "Answer")
            }
            let withoutReasoning = session.appendNewMessage(role: .assistant)

            session.finalizeInterruptedReasoning()

            #expect(answered.document == "Answer")
            #expect(withoutReasoning.document.isEmpty)
        }
    }
}

private extension ConversationInterruptedReasoningTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Interrupted Reasoning Tests \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }
}

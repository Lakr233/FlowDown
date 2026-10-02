//
//  ConversationSearchTests.swift
//  FlowDownUnitTests
//

@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationSearchTests {
    @Test
    @MainActor
    func searchMessageWithLongerLowercaseForm_returnsPreview() async throws {
        try await withTemporarySession { conversation, session in
            // "İ" lowercases to two scalars, so a lowercased copy is longer.
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "İstanbul'a gidiyorum")
            }
            session.save()

            for query in ["gidiyorum", "GIDIYORUM"] {
                let results = ConversationManager.shared
                    .searchConversations(query: query)
                    .filter { $0.conversation.id == conversation.id }
                #expect(results.count == 1)
                #expect(results.first?.matchType == .message)
                #expect(results.first?.messagePreview?.contains("gidiyorum") == true)
            }
        }
    }
}

private extension ConversationSearchTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (Conversation, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Search Tests \(UUID().uuidString.prefix(8))")
        }
        // Search walks the manager's cached list, so load the new row into it.
        ConversationManager.shared.scanAll()
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(conversation, session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }
}

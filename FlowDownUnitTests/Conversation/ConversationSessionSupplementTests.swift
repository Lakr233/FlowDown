//
//  ConversationSessionSupplementTests.swift
//  FlowDownUnitTests
//

@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationSessionSupplementTests {
    @Test
    @MainActor
    func discardEmptyFollowUpReply_keepsEveryWebSearchRow() async throws {
        try await withTemporarySession { conversation, session in
            try await append(.user, "First question", to: session)
            let firstSearch = try await append(.webSearch, to: session)
            try await append(.assistant, "First answer", to: session)
            try await append(.user, "Second question", to: session)
            let secondSearch = try await append(.webSearch, to: session)
            let followUp = try await append(.assistant, to: session)
            session.save()

            session.discard(messageIdentifier: followUp.objectId)

            let stored = sdb.listMessages(within: conversation.id).map(\.objectId)
            #expect(!stored.contains(followUp.objectId))
            #expect(stored.contains(firstSearch.objectId))
            #expect(stored.contains(secondSearch.objectId))
        }
    }

    @Test
    @MainActor
    func deleteMessage_removesOnlyTheSupplementRowsDirectlyBeforeIt() async throws {
        try await withTemporarySession { conversation, session in
            try await append(.user, "First question", to: session)
            let earlierHint = try await append(.hint, "Earlier hint", to: session)
            let firstAnswer = try await append(.assistant, "First answer", to: session)
            try await append(.user, "Second question", to: session)
            let search = try await append(.webSearch, to: session)
            let hint = try await append(.hint, "Attached hint", to: session)
            let secondAnswer = try await append(.assistant, "Second answer", to: session)
            session.save()

            session.delete(messageIdentifier: secondAnswer.objectId)
            try await waitUntil {
                !sdb.listMessages(within: conversation.id).contains { $0.objectId == secondAnswer.objectId }
            }

            let stored = sdb.listMessages(within: conversation.id).map(\.objectId)
            #expect(stored.contains(earlierHint.objectId))
            #expect(stored.contains(firstAnswer.objectId))
            #expect(!stored.contains(search.objectId))
            #expect(!stored.contains(hint.objectId))
        }
    }
}

private extension ConversationSessionSupplementTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (Conversation, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Supplement Tests \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(conversation, session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }

    /// Appends a row, then waits a moment so every row gets its own creation
    /// time; the conversation is ordered by it.
    @MainActor
    @discardableResult
    func append(
        _ role: Message.Role,
        _ document: String = "",
        to session: ConversationSession,
    ) async throws -> Message {
        let message = session.appendNewMessage(role: role) {
            $0.update(\.document, to: document)
        }
        try await Task.sleep(for: .milliseconds(5))
        return message
    }

    @MainActor
    func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw NSError(
            domain: "ConversationSessionSupplementTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition."],
        )
    }
}

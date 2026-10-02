//
//  StorageConversationLifecycleTests.swift
//  FlowDownUnitTests
//

import Foundation
@testable import Storage
import Testing

@Suite(.serialized)
struct StorageConversationLifecycleTests {
    @Test
    func duplicateConversation_keepsCreationOrderSoDeleteAfterKeepsHistory() throws {
        try withTemporaryStorage { storage in
            let conversation = storage.conversationMake { $0.update(\.title, to: "Original") }
            insertMessages([.user, .assistant, .user, .assistant], into: conversation.id, storage: storage)

            let duplicateID = try #require(
                storage.conversationDuplicate(identifier: conversation.id) { _ in },
            )
            let duplicate = storage.listMessages(within: duplicateID)

            try #require(duplicate.count == 4)
            #expect(Set(duplicate.map(\.creation)).count == duplicate.count)
            #expect(duplicate.map(\.document) == ["Message 0", "Message 1", "Message 2", "Message 3"])

            storage.deleteAfter(messageIdentifier: duplicate[1].id)

            #expect(storage.listMessages(within: duplicateID).map(\.id) == [duplicate[0].id, duplicate[1].id])
        }
    }

    @Test
    func deleteSupplementMessage_removesOnlyTheRowsDirectlyBefore() throws {
        try withTemporaryStorage { storage in
            let conversation = storage.conversationMake { $0.update(\.title, to: "Supplements") }
            let ids = insertMessages(
                [.user, .hint, .webSearch, .assistant, .user, .webSearch, .hint, .assistant],
                into: conversation.id,
                storage: storage,
            ).map(\.id)
            let remaining = [ids[0], ids[1], ids[2], ids[3], ids[4], ids[7]]

            storage.deleteSupplementMessage(nextTo: ids[7])
            #expect(storage.listMessages(within: conversation.id).map(\.id) == remaining)

            storage.deleteSupplementMessage(nextTo: ids[4])
            #expect(storage.listMessages(within: conversation.id).map(\.id) == remaining)
        }
    }

    @Test
    func eraseAllConversations_removesConversationSummaries() throws {
        try withTemporaryStorage { storage in
            let conversation = storage.conversationMake { $0.update(\.title, to: "Summarized") }
            let summary = ConversationSummary(deviceId: Storage.deviceId, conversationId: conversation.id)
            try storage.insertOrUpdateSummary(summary)
            #expect(try storage.getRecentSummaries().count == 1)

            storage.conversationsDrop()

            #expect(try storage.getRecentSummaries().isEmpty)
            #expect(try storage.getSummary(forConversation: conversation.id) == nil)
            let queues = storage.pendingUploadList(tables: [ConversationSummary.tableName])
            #expect(queues.contains { $0.objectId == summary.id && $0.changes == .delete })
        }
    }
}

private extension StorageConversationLifecycleTests {
    func withTemporaryStorage(_ body: (Storage) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageConversationLifecycleTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = try Storage.makeForTesting(databaseDir: directory)
        try body(storage)
    }

    /// Inserts one message per role, one second apart, so the order is fixed.
    @discardableResult
    func insertMessages(
        _ roles: [Message.Role],
        into conversationID: Conversation.ID,
        storage: Storage,
    ) -> [Message] {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let messages: [Message] = roles.enumerated().map { index, role in
            let message = storage.makeMessage(with: conversationID, skipSave: true) {
                $0.update(\.role, to: role)
                $0.update(\.document, to: "Message \(index)")
            }
            message.creation = base.addingTimeInterval(TimeInterval(index))
            return message
        }
        storage.messagePut(messages: messages)
        return messages
    }
}

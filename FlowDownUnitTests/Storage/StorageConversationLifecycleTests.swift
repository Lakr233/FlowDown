//
//  StorageConversationLifecycleTests.swift
//  FlowDownUnitTests
//

import Foundation
@testable import Storage
// Testing has an Attachment of its own
import class Storage.Attachment
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

    /// A copy of a removed row would be uploaded as an insert that nothing deletes later.
    @Test
    func duplicateConversation_copiesAndQueuesOnlyRowsInUse() throws {
        try withTemporaryStorage { storage in
            let conversation = storage.conversationMake { $0.update(\.title, to: "Original") }
            let messages = insertMessages([.user, .assistant, .user, .assistant], into: conversation.id, storage: storage)

            // message 0 in use: one removed attachment, one in use
            makeAttachment(named: "removed", for: messages[0], storage: storage)
            try storage.attachmentsMarkDelete(messageIds: [messages[0].id])
            makeAttachment(named: "kept", for: messages[0], storage: storage)
            // message 1 removed: one attachment removed with it, one still marked in use
            makeAttachment(named: "cascaded", for: messages[1], storage: storage)
            storage.delete(messageIdentifier: messages[1].id)
            makeAttachment(named: "orphan", for: messages[1], storage: storage)

            let tables = [Conversation.tableName, Message.tableName, Attachment.tableName]
            let queuedBefore = Set(storage.pendingUploadList(tables: tables).map(\.id))

            let duplicateID = try #require(
                storage.conversationDuplicate(identifier: conversation.id) { _ in },
            )

            let duplicate = storage.listMessages(within: duplicateID)
            try #require(duplicate.count == 3)
            #expect(duplicate.map(\.document) == ["Message 0", "Message 2", "Message 3"])
            #expect(duplicate.map(\.role) == [.user, .user, .assistant])
            #expect(duplicate.map(\.creation) == [messages[0], messages[2], messages[3]].map(\.creation))
            #expect(Set(duplicate.map(\.id)).isDisjoint(with: messages.map(\.id)))

            let copiedAttachments = duplicate.flatMap { storage.attachment(for: $0.id) }
            try #require(copiedAttachments.count == 1)
            #expect(copiedAttachments[0].messageId == duplicate[0].id)
            #expect(copiedAttachments[0].name == "kept")
            #expect(copiedAttachments[0].data == Data("kept data".utf8))
            #expect(copiedAttachments[0].representedDocument == "kept document")

            // everything queued by the duplication: inserts for the copies above and nothing else
            let queued = storage.pendingUploadList(tables: tables).filter { !queuedBefore.contains($0.id) }
            #expect(queued.allSatisfy { $0.changes == .insert })
            #expect(Set(queued.map { "\($0.tableName) \($0.objectId)" }) == Set(
                ["\(Conversation.tableName) \(duplicateID)"]
                    + duplicate.map { "\(Message.tableName) \($0.id)" }
                    + copiedAttachments.map { "\(Attachment.tableName) \($0.id)" },
            ))
            #expect(queued.count == 5)
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

    func makeAttachment(named name: String, for message: Message, storage: Storage) {
        _ = storage.attachmentMake(with: message.id) {
            $0.name = name
            $0.data = Data("\(name) data".utf8)
            $0.representedDocument = "\(name) document"
        }
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

//
//  Storage+Message.swift
//  Storage
//
//  Created by 秋星桥 on 1/31/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    typealias MessageMakeInitDataBlock = (Message) -> Void
    func makeMessage(
        with conversationID: Conversation.ID,
        skipSave: Bool = false,
        _ block: MessageMakeInitDataBlock?
    ) -> Message {
        let message = Message(deviceId: Self.deviceId)
        message.conversationId = conversationID

        if let block {
            block(message)
        }

        message.creation = .now
        message.modified = message.creation

        if skipSave {
            return message
        }

        try? runTransaction {
            try $0.insert([message], intoTable: Message.tableName)
            try self.pendingUploadEnqueue(sources: [(message, .insert)], handle: $0)
        }

        return message
    }

    func listMessages(within conv: Conversation.ID) -> [Message] {
        let objects: [Message]? = try? db.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == conv && Message.Properties.removed == false,
            orderBy: [
                Message.Properties.creation
                    .order(.ascending),
            ],
        )

        return objects ?? []
    }

    func messagePut(object: Message) {
        messagePut(messages: [object])
    }

    func messagePut(messages: [Message]) {
        guard !messages.isEmpty else {
            return
        }

        try? putSyncable(messages)

        // 触发同步
        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func conversationIdentifierLookup(identifier: Message.ID) -> Conversation.ID? {
        guard !identifier.isEmpty else {
            return nil
        }

        let message: Message? = try? db.getObject(
            fromTable: Message.tableName,
            where: Message.Properties.objectId == identifier && Message.Properties.removed == false,
        )

        guard let identifier = message?.conversationId else {
            assertionFailure()
            return nil
        }
        return identifier
    }

    /// Deletes the supplement rows (web search, hints) directly before the message,
    /// stopping at the first other row so earlier turns keep theirs.
    func deleteSupplementMessage(nextTo messageIdentifier: Message.ID) {
        guard !messageIdentifier.isEmpty else {
            return
        }

        // list all messages in the same conversation
        guard let message: Message = try? db.getObject(
            fromTable: Message.tableName,
            where: Message.Properties.objectId == messageIdentifier,
        ) else {
            assertionFailure()
            return
        }

        guard let messages: [Message] = try? db.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == message.conversationId
                && Message.Properties.removed == false
                && Message.Properties.objectId != messageIdentifier
                && Message.Properties.creation <= message.creation,
            orderBy: [
                Message.Properties.creation.order(.descending),
            ],
        ), !messages.isEmpty else {
            return
        }

        let deletetMessages = messages.prefix(while: { $0.role.isSupplementKind })
        guard !deletetMessages.isEmpty else {
            return
        }

        try? messageMarkDelete(messageIds: deletetMessages.compactMap(\.objectId))
    }

    func delete(messageIdentifier: Message.ID) {
        try? messageMarkDelete(messageIds: [messageIdentifier])
    }

    func deleteAfter(messageIdentifier: Message.ID) {
        try? messageMarkDeleteAfter(messageId: messageIdentifier)
    }

    /// 标记消息删除
    /// - Parameters:
    ///   - messageIds: 消息ID集合
    func messageMarkDelete(messageIds: [Message.ID]) throws {
        guard !messageIds.isEmpty else {
            return
        }

        let messages: [Message] = try db.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.objectId.in(messageIds),
        )

        try markMessagesDeleted(messages)
    }

    /// 标记消息删除
    /// - Parameters:
    ///   - conversationID: 会话ID
    ///   - handle: The handle of the enclosing transaction.
    func messageMarkDelete(conversationID: Conversation.ID, handle: Handle) throws {
        guard !conversationID.isEmpty else {
            return
        }

        let messages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == conversationID
                && Message.Properties.removed == false,
        )

        try markMessagesDeleted(messages, handle: handle)
    }

    /// 标记消息删除
    /// - Parameter messageId: 消息ID
    func messageMarkDeleteAfter(messageId: Message.ID) throws {
        guard !messageId.isEmpty else {
            return
        }

        guard let message: Message = try? db.getObject(
            fromTable: Message.tableName,
            where: Message.Properties.objectId == messageId,
        ) else {
            assertionFailure()
            return
        }

        let condition: Condition = Message.Properties.objectId != messageId &&
            Message.Properties.creation >= message.creation &&
            Message.Properties.conversationId == message.conversationId

        let messages: [Message] = try db.getObjects(fromTable: Message.tableName, where: condition)

        try markMessagesDeleted(messages)
    }

    /// 标记消息删除
    /// - Parameters:
    ///   - skipAttachment: 是否跳过附件
    ///   - handle: The handle of the enclosing transaction.
    func messageMarkDelete(skipAttachment: Bool = false, handle: Handle) throws {
        let messages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.removed == false,
        )

        try markMessagesDeleted(messages, skipAttachment: skipAttachment, handle: handle)
    }

    /// Marks the messages removed, together with their attachments unless skipped, and queues the deletions for upload.
    private func markMessagesDeleted(
        _ messages: [Message],
        skipAttachment: Bool = false,
        handle: Handle? = nil,
    ) throws {
        guard !messages.isEmpty else {
            return
        }

        let deletedIds = messages.map(\.objectId)
        let modified = Date.now
        for message in messages {
            message.removed = true
            message.markModified(modified)
        }

        let update = StatementUpdate().update(table: Message.tableName)
            .set(Message.Properties.removed)
            .to(true)
            .set(Message.Properties.modified)
            .to(modified)
            .where(Message.Properties.objectId.in(deletedIds))

        if let handle {
            try handle.exec(update)
        } else {
            try db.exec(update)
        }

        if !skipAttachment {
            try attachmentsMarkDelete(messageIds: deletedIds, handle: handle)
        }

        try pendingUploadEnqueue(sources: messages.map { ($0, .delete) }, handle: handle)
    }
}

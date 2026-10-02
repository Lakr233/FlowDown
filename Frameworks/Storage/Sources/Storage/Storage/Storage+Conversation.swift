//
//  Storage+Conversation.swift
//  Storage
//
//  Created by 秋星桥 on 1/31/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    func conversationList() -> [Conversation] {
        (
            try? db.getObjects(
                fromTable: Conversation.tableName,
                where: Conversation.Properties.removed == false,
                orderBy: [
                    Conversation.Properties.creation
                        .order(.descending),
                ],
            ),
        ) ?? []
    }

    func conversationListAllIdentifiers() -> Set<Conversation.ID> {
        let identifiers = try? db.getColumn(
            on: Conversation.Properties.objectId,
            fromTable: Conversation.tableName,
            where: Conversation.Properties.removed == false,
        )
        let items = identifiers?.map(\.stringValue) ?? []
        return .init(items)
    }

    typealias ConversationMakeInitDataBlock = (Conversation) -> Void
    func conversationMake(skipSave: Bool = false, _ block: ConversationMakeInitDataBlock?) -> Conversation {
        let object = Conversation(deviceId: Self.deviceId)
        if let block {
            block(object)
        }

        object.creation = .now
        object.modified = object.creation

        if skipSave {
            return object
        }

        try? runTransaction {
            try $0.insert([object], intoTable: Conversation.tableName)
            try self.pendingUploadEnqueue(sources: [(object, .insert)], handle: $0)
        }

        return object
    }

    func conversationUpdate(object: Conversation) {
        conversationUpdate(objects: [object])
    }

    func conversationUpdate(objects: [Conversation]) {
        guard !objects.isEmpty else {
            return
        }

        try? putSyncable(objects)

        // 触发同步
        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func conversationWith(identifier: Conversation.ID) -> Conversation? {
        try? db.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == identifier && Conversation.Properties.removed == false,
        )
    }

    func conversationIds(by messageIds: [Message.ID]) -> [Conversation.ID: [Message.ID]] {
        guard !messageIds.isEmpty else {
            return [:]
        }

        let select = StatementSelect()
            .select(Message.Properties.conversationId, Message.Properties.objectId)
            .from(Message.tableName)
            .where(Message.Properties.objectId.in(messageIds))

        let rows = try? db.getRows(from: select)

        guard let rows, !rows.isEmpty else { return [:] }

        var result: [Conversation.ID: [Message.ID]] = [:]
        for row in rows {
            let conversationId = row[0].stringValue
            let messageId = row[1].stringValue
            result[conversationId, default: []].append(messageId)
        }
        return result
    }

    func conversationRemove(conversationWith identifier: Conversation.ID) {
        guard !identifier.isEmpty else {
            return
        }

        try? runTransaction { [weak self] in
            guard let self else { return }
            try conversationMarkDelete(conversationId: identifier, handle: $0)
        }
    }

    @discardableResult
    func conversationDuplicate(
        identifier: Conversation.ID,
        customize: @escaping (Conversation) -> Void
    ) -> Conversation.ID? {
        guard !identifier.isEmpty else {
            return nil
        }

        var ans: Conversation.ID?
        try? db.run { handler -> Bool in
            do {
                let ret = try self.executeDuplicationTransaction(
                    identifier: identifier,
                    handle: handler,
                    customize: customize,
                )
                ans = ret
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
        return ans
    }

    private func executeDuplicationTransaction(
        identifier: Conversation.ID,
        handle: Handle,
        customize: (Conversation) -> Void,
    ) throws -> Conversation.ID {
        let conv: Conversation? = try handle.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == identifier,
        )
        guard let conv else { throw NSError() }

        let nowDate = Date.now
        // 更新
        conv.objectId = UUID().uuidString

        customize(conv)

        conv.creation = nowDate
        conv.modified = nowDate

        try handle.insert([conv], intoTable: Conversation.tableName)

        let newIdentifier = conv.objectId
        guard newIdentifier != identifier else {
            assertionFailure()
            throw NSError()
        }

        var pendingUpload: [(source: any Syncable, changes: UploadQueue.Changes)] = [
            (conv, .insert),
        ]

        let messages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == identifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ],
        )

        var oldMessageIdentifierSet = Set<String>()
        for message in messages {
            let oldMessageId = message.objectId
            oldMessageIdentifierSet.insert(oldMessageId)

            // new
            // Copies keep their original creation, which orders the conversation
            // and bounds deleteAfter to the rows that really come later.
            message.objectId = UUID().uuidString
            message.conversationId = newIdentifier
            message.modified = nowDate

            try handle.insert(message, intoTable: Message.tableName)
            let newMessageId = message.objectId

            var oldAttachmentIdentifierSet = Set<String>()
            let attachments: [Attachment] = try handle.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == oldMessageId,
            )
            for attachment in attachments {
                oldAttachmentIdentifierSet.insert(attachment.id)

                // new
                attachment.objectId = UUID().uuidString
                attachment.messageId = message.objectId
                attachment.modified = nowDate

                try handle.insert(attachment, intoTable: Attachment.tableName)
            }
            let newAttachments: [Attachment] = try handle.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == newMessageId,
            )

            for attachment in newAttachments {
                guard !oldAttachmentIdentifierSet.contains(attachment.id) else {
                    assertionFailure()
                    throw NSError()
                }
            }

            pendingUpload.append((message, .insert))
            pendingUpload.append(contentsOf: newAttachments.map { ($0, .insert) })
        }

        let newMessages: [Message] = try handle.getObjects(
            fromTable: Message.tableName,
            where: Message.Properties.conversationId == newIdentifier,
            orderBy: [
                Message.Properties.creation.order(.ascending),
            ],
        )

        for message in newMessages {
            guard !oldMessageIdentifierSet.contains(message.objectId) else {
                assertionFailure()
                throw NSError()
            }
        }

        try pendingUploadEnqueue(sources: pendingUpload, handle: handle)

        return newIdentifier
    }

    func conversationsDrop() {
        try? db.run { handle -> Bool in
            do {
                try self.executeEraseAllConversations(handle: handle)
                return true
            } catch {
                assertionFailure(error.localizedDescription)
                return false
            }
        }
    }

    func conversationMarkDelete(conversationId: Conversation.ID, handle: Handle) throws {
        guard !conversationId.isEmpty else {
            return
        }

        let conv: Conversation? = try handle.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == conversationId,
        )

        guard let conv else { return }

        conv.removed = true
        conv.markModified()

        try messageMarkDelete(conversationID: conversationId, handle: handle)

        let update = StatementUpdate().update(table: Conversation.tableName)
            .set(Conversation.Properties.removed)
            .to(true)
            .set(Conversation.Properties.modified)
            .to(conv.modified)
            .where(Conversation.Properties.objectId == conversationId)
        try handle.exec(update)

        try pendingUploadEnqueue(sources: [(conv, .delete)], handle: handle)
    }

    func conversationMarkDelete(handle: Handle) throws {
        let convs: [Conversation] = try handle.getObjects(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.removed == false,
            orderBy: [Conversation.Properties.modified.order(.ascending)],
        )

        guard !convs.isEmpty else {
            return
        }

        let modified = Date.now
        for conv in convs {
            conv.removed = true
            conv.markModified(modified)
        }

        let objectIds = convs.map(\.objectId)
        let update = StatementUpdate().update(table: Conversation.tableName)
            .set(Conversation.Properties.removed)
            .to(true)
            .set(Conversation.Properties.modified)
            .to(modified)
            .where(Conversation.Properties.objectId.in(objectIds))

        try handle.exec(update)

        try pendingUploadEnqueue(sources: convs.map { ($0, .delete) }, handle: handle)
    }

    private func executeEraseAllConversations(handle: Handle) throws {
        try conversationMarkDelete(handle: handle)
        try messageMarkDelete(skipAttachment: true, handle: handle)
        try attachmentsMarkDelete(handle: handle)

        // Summaries are injected into new chats, so they go with the conversations.
        let summaries: [ConversationSummary] = try handle.getObjects(
            fromTable: ConversationSummary.tableName,
            where: ConversationSummary.Properties.removed == false,
        )
        guard !summaries.isEmpty else {
            return
        }

        let modified = Date.now
        for summary in summaries {
            summary.removed = true
            summary.markModified(modified)
        }

        let update = StatementUpdate().update(table: ConversationSummary.tableName)
            .set(ConversationSummary.Properties.removed)
            .to(true)
            .set(ConversationSummary.Properties.modified)
            .to(modified)
            .where(ConversationSummary.Properties.objectId.in(summaries.map(\.objectId)))
        try handle.exec(update)

        try pendingUploadEnqueue(sources: summaries.map { ($0, .delete) }, handle: handle)
    }
}

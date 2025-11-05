//
//  Storage+Sync.swift
//  Storage
//
//  Created by king on 2025/10/17.
//

import CloudKit
import Foundation
import WCDBSwift

package extension Storage {
    func handleRemoteDeleted(
        deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)],
        handle: Handle? = nil
    ) throws {
        guard !deletions.isEmpty else {
            return
        }

        let transaction: (Handle) throws -> Void = { [weak self] in
            guard let self else { return }

            for deletion in deletions {
                let recordID = deletion.recordID
                guard let (objectId, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }

                try handleRemoteDeleted(tableName: tableName, objectId: objectId, handle: $0)

                try $0.delete(
                    fromTable: SyncMetadata.tableName,
                    where: SyncMetadata.Properties.recordName == recordID.recordName
                )
            }
        }

        if let handle {
            try handle.run(transaction: transaction)
        } else {
            try db.run(transaction: transaction)
        }
    }

    private func handleRemoteDeleted(tableName: String, objectId: String, handle: Handle) throws {
        switch tableName {
        case Conversation.tableName:
            try handleRemoteDeletedConversation(conversationId: objectId, handle: handle)
        case Message.tableName:
            try handleRemoteDeletedMessage(messageId: objectId, handle: handle)
        case Attachment.tableName:
            try handleRemoteDeletedAttachment(attachmentId: objectId, handle: handle)
        case CloudModel.tableName:
            try handleRemoteDeletedCloudModel(objectId: objectId, handle: handle)
        case ModelContextServer.tableName:
            try handleRemoteDeletedModelContextServer(objectId: objectId, handle: handle)
        case Memory.tableName:
            try handleRemoteDeletedMemory(objectId: objectId, handle: handle)
        case ChatTemplateRecord.tableName:
            try handleRemoteDeletedChatTemplate(objectId: objectId, handle: handle)
        default:
            break
        }
    }

    private func handleRemoteDeletedConversation(conversationId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == conversationId
        )

        Logger.syncEngine.info("handleRemoteDeletedConversation \(conversationId)")
    }

    private func handleRemoteDeletedMessage(messageId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: Message.tableName,
            where: Message.Properties.objectId == messageId
        )

        Logger.syncEngine.info("handleRemoteDeletedMessage \(messageId)")
    }

    private func handleRemoteDeletedAttachment(attachmentId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: Attachment.tableName,
            where: Attachment.Properties.objectId == attachmentId
        )

        Logger.syncEngine.info("handleRemoteDeletedAttachment \(attachmentId)")
    }

    private func handleRemoteDeletedCloudModel(objectId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == objectId
        )

        Logger.syncEngine.info("handleRemoteDeletedCloudModel \(objectId)")
    }

    private func handleRemoteDeletedModelContextServer(objectId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == objectId
        )

        Logger.syncEngine.info("handleRemoteDeletedModelContextServer \(objectId)")
    }

    private func handleRemoteDeletedMemory(objectId: String, handle: Handle, modified _: Date = .now) throws {
        try handle.delete(
            fromTable: Memory.tableName,
            where: Memory.Properties.objectId == objectId
        )

        Logger.syncEngine.info("handleRemoteDeletedMemory \(objectId)")
    }

    private func handleRemoteDeletedChatTemplate(objectId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: ChatTemplateRecord.tableName,
            where: ChatTemplateRecord.Properties.objectId == objectId
        )

        Logger.syncEngine.info("handleRemoteDeletedChatTemplate \(objectId)")
    }
}

package extension Storage {
    func handleRemoteUpsert(
        modifications: [CKRecord],
        handle: Handle? = nil
    ) throws {
        guard !modifications.isEmpty else {
            return
        }

        let transaction: (Handle) throws -> Void = { [weak self] in
            guard let self else { return }

            for modification in modifications {
                let recordID = modification.recordID
                guard let (_, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }
                try handleRemoteUpsert(tableName: tableName, serverRecord: modification, handle: $0)
                let metadata = SyncMetadata(record: modification)
                try $0.insertOrReplace([metadata], intoTable: SyncMetadata.tableName)
            }
        }

        if let handle {
            try handle.run(transaction: transaction)
        } else {
            try db.run(transaction: transaction)
        }
    }

    private func handleRemoteUpsert(tableName: String, serverRecord: CKRecord, handle: Handle) throws {
        switch tableName {
        case Conversation.tableName:
            try handleRemoteUpsertConversation(serverRecord: serverRecord, handle: handle)
        case Message.tableName:
            try handleRemoteUpsertMessage(serverRecord: serverRecord, handle: handle)
        case Attachment.tableName:
            try handleRemoteUpsertAttachment(serverRecord: serverRecord, handle: handle)
        case CloudModel.tableName:
            try handleRemoteUpsertCloudModel(serverRecord: serverRecord, handle: handle)
        case ModelContextServer.tableName:
            try handleRemoteUpsertModelContextServer(serverRecord: serverRecord, handle: handle)
        case Memory.tableName:
            try handleRemoteUpsertMemory(serverRecord: serverRecord, handle: handle)
        case ChatTemplateRecord.tableName:
            try handleRemoteUpsertChatTemplate(serverRecord: serverRecord, handle: handle)
        default:
            break
        }
    }

    private func handleRemoteUpsertConversation(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? Conversation.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertConversation decodePayload fail")
            return
        }

        let localObject: Conversation? = try? handle.getObject(
            fromTable: Conversation.tableName,
            where: Conversation.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: Conversation.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: Conversation.tableName)
    }

    private func handleRemoteUpsertMessage(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? Message.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertMessage decodePayload fail")
            return
        }

        let localObject: Message? = try? handle.getObject(
            fromTable: Message.tableName,
            where: Message.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: Message.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(source: localObject, changes: .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: Message.tableName)
    }

    private func handleRemoteUpsertAttachment(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? Attachment.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertAttachment decodePayload fail")
            return
        }

        let localObject: Attachment? = try? handle.getObject(
            fromTable: Attachment.tableName,
            where: Attachment.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: Attachment.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: Attachment.tableName)
    }

    private func handleRemoteUpsertCloudModel(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? CloudModel.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertCloudModel decodePayload fail")
            return
        }

        let localObject: CloudModel? = try? handle.getObject(
            fromTable: CloudModel.tableName,
            where: CloudModel.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: CloudModel.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: CloudModel.tableName)
    }

    private func handleRemoteUpsertModelContextServer(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? ModelContextServer.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertModelContextServer decodePayload fail")
            return
        }

        let localObject: ModelContextServer? = try? handle.getObject(
            fromTable: ModelContextServer.tableName,
            where: ModelContextServer.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            /// 这些状态不需要同步
            remoteObject.connectionStatus = .disconnected
            remoteObject.lastConnected = nil
            remoteObject.capabilities = .init([])

            try? handle.insertOrReplace([remoteObject], intoTable: ModelContextServer.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        /// 这些状态不需要同步
        remoteObject.connectionStatus = localObject.connectionStatus
        remoteObject.lastConnected = localObject.lastConnected
        remoteObject.capabilities = localObject.capabilities

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: ModelContextServer.tableName)
    }

    private func handleRemoteUpsertMemory(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? Memory.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertMemory decodePayload fail")
            return
        }

        let localObject: Memory? = try? handle.getObject(
            fromTable: Memory.tableName,
            where: Memory.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: Memory.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: Memory.tableName)
    }

    private func handleRemoteUpsertChatTemplate(serverRecord: CKRecord, handle: Handle) throws {
        guard let payload = serverRecord.payloadData else { return }

        guard let remoteObject = try? ChatTemplateRecord.decodePayload(payload) else {
            Logger.syncEngine.error("handleRemoteUpsertChatTemplate decodePayload fail")
            return
        }

        let localObject: ChatTemplateRecord? = try? handle.getObject(
            fromTable: ChatTemplateRecord.tableName,
            where: ChatTemplateRecord.Properties.objectId == remoteObject.objectId
        )

        guard let localObject else {
            try? handle.insertOrReplace([remoteObject], intoTable: ChatTemplateRecord.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            try? pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            return
        }

        // 云端最新的
        try? handle.insertOrReplace([remoteObject], intoTable: ChatTemplateRecord.tableName)
    }
}

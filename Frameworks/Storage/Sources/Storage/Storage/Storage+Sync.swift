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
    private func logDecodeFailure(tableName: String, recordID: CKRecord.ID, payloadSize: Int?) {
        Logger.syncEngine.errorFile("handleRemoteUpsert \(tableName) decode payload failed record=\(recordID.recordName) payloadSize=\(payloadSize ?? -1)")
    }

    func handleRemoteDeleted(
        deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)],
        handle: Handle,
    ) throws {
        guard !deletions.isEmpty else {
            return
        }

        try handle.run(transaction: { [weak self] in
            guard let self else { return }

            for deletion in deletions {
                let recordID = deletion.recordID
                guard let (objectId, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }

                try handleRemoteDeleted(tableName: tableName, objectId: objectId, handle: $0)

                try $0.delete(
                    fromTable: SyncMetadata.tableName,
                    where: SyncMetadata.Properties.recordName == recordID.recordName,
                )
            }
        })
    }

    private func handleRemoteDeleted(tableName: String, objectId: String, handle: Handle) throws {
        switch tableName {
        case Conversation.tableName:
            try deleteRemoteRow(Conversation.self, objectId: objectId, handle: handle)
        case Message.tableName:
            try deleteRemoteRow(Message.self, objectId: objectId, handle: handle)
        case Attachment.tableName:
            try deleteRemoteRow(Attachment.self, objectId: objectId, handle: handle)
        case CloudModel.tableName:
            try deleteRemoteRow(CloudModel.self, objectId: objectId, handle: handle)
        case ModelContextServer.tableName:
            try deleteRemoteRow(ModelContextServer.self, objectId: objectId, handle: handle)
        case Memory.tableName:
            try deleteRemoteRow(Memory.self, objectId: objectId, handle: handle)
        case ChatTemplateRecord.tableName:
            try deleteRemoteRow(ChatTemplateRecord.self, objectId: objectId, handle: handle)
        case ConversationSummary.tableName:
            try deleteRemoteRow(ConversationSummary.self, objectId: objectId, handle: handle)
        default:
            break
        }
    }

    private func deleteRemoteRow<T: Syncable & SyncQueryable>(_: T.Type, objectId: String, handle: Handle) throws {
        try handle.delete(
            fromTable: T.tableName,
            where: T.SyncQuery.objectId == objectId,
        )

        Logger.syncEngine.infoFile("handleRemoteDeleted\(T.tableName) \(objectId)")
    }
}

package extension Storage {
    func handleRemoteUpsert(modifications: [CKRecord]) throws {
        guard !modifications.isEmpty else {
            return
        }

        try db.run(transaction: { [weak self] in
            guard let self else { return }

            for modification in modifications {
                let recordID = modification.recordID
                guard let (_, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }
                try handleRemoteUpsert(tableName: tableName, serverRecord: modification, handle: $0)
                let metadata = SyncMetadata(record: modification)
                try $0.insertOrReplace([metadata], intoTable: SyncMetadata.tableName)
            }
        })
    }

    private func handleRemoteUpsert(tableName: String, serverRecord: CKRecord, handle: Handle) throws {
        switch tableName {
        case Conversation.tableName:
            try handleRemoteUpsert(
                Conversation.self,
                serverRecord: serverRecord,
                handle: handle,
                propagatesEnqueueError: true,
            )
        case Message.tableName:
            try handleRemoteUpsert(Message.self, serverRecord: serverRecord, handle: handle)
        case Attachment.tableName:
            try handleRemoteUpsert(Attachment.self, serverRecord: serverRecord, handle: handle)
        case CloudModel.tableName:
            try handleRemoteUpsert(CloudModel.self, serverRecord: serverRecord, handle: handle)
        case ModelContextServer.tableName:
            try handleRemoteUpsert(
                ModelContextServer.self,
                serverRecord: serverRecord,
                handle: handle,
            ) { remote, local in
                // 这些状态不需要同步
                remote.connectionStatus = local?.connectionStatus ?? .disconnected
                remote.lastConnected = local?.lastConnected
                remote.capabilities = local?.capabilities ?? .init([])
            }
        case Memory.tableName:
            try handleRemoteUpsert(Memory.self, serverRecord: serverRecord, handle: handle)
        case ChatTemplateRecord.tableName:
            try handleRemoteUpsert(ChatTemplateRecord.self, serverRecord: serverRecord, handle: handle)
        case ConversationSummary.tableName:
            try handleRemoteUpsert(ConversationSummary.self, serverRecord: serverRecord, handle: handle)
        default:
            break
        }
    }

    /// Merges one server record: a newer local row is queued for upload again, otherwise the server copy is written.
    /// - Parameters:
    ///   - propagatesEnqueueError: Whether a failed re-enqueue throws, which rolls back the whole batch.
    ///   - keepLocalState: Restores the fields that are not synced before the server copy is written;
    ///     its second argument is the local row, or nil when there is none.
    private func handleRemoteUpsert<T: Syncable & SyncQueryable & TableEncodable>(
        _: T.Type,
        serverRecord: CKRecord,
        handle: Handle,
        propagatesEnqueueError: Bool = false,
        keepLocalState: ((T, T?) -> Void)? = nil,
    ) throws {
        guard let payload = serverRecord.payloadData else {
            logDecodeFailure(tableName: T.tableName, recordID: serverRecord.recordID, payloadSize: nil)
            return
        }

        guard let remoteObject = try? T.decodePayload(payload) else {
            logDecodeFailure(tableName: T.tableName, recordID: serverRecord.recordID, payloadSize: payload.count)
            return
        }

        let localObject: T? = try? handle.getObject(
            fromTable: T.tableName,
            where: T.SyncQuery.objectId == remoteObject.objectId,
        )

        guard let localObject else {
            keepLocalState?(remoteObject, nil)
            try? handle.insertOrReplace([remoteObject], intoTable: T.tableName)
            return
        }

        let localMilliseconds = localObject.modified.millisecondsSince1970
        let lastModifiedMilliseconds = serverRecord.lastModifiedMilliseconds
        if localMilliseconds == lastModifiedMilliseconds {
            return
        }

        if localMilliseconds > lastModifiedMilliseconds {
            // 本地是最新的
            do {
                try pendingUploadEnqueue(sources: [(localObject, .update)], skipEnqueueHandler: true, handle: handle)
            } catch {
                if propagatesEnqueueError {
                    throw error
                }
            }
            return
        }

        // 云端最新的
        keepLocalState?(remoteObject, localObject)
        try? handle.insertOrReplace([remoteObject], intoTable: T.tableName)
    }
}

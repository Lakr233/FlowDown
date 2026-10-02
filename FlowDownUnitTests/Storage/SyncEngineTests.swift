//
//  SyncEngineTests.swift
//  FlowDownUnitTests
//

import CloudKit
import Foundation
@testable import Storage
import Testing

/// Drives `SyncEngine` event handling against a temporary database and a `MockSyncEngine`.
/// Serialized because the cases change the shared Sync Scope preferences.
@Suite(.serialized)
struct SyncEngineTests {
    private static let zoneID = CKRecordZone.ID(zoneName: "FlowDownSync", ownerName: CKCurrentUserDefaultName)
    private static let recordType: CKRecord.RecordType = "SyncObject"

    // MARK: - Account change

    @Test
    func accountSignOut_disabledGroup_keepsLocalRowsAndPendingUploads() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.models, enabled: false)
        defer { restoreGroup() }

        let model = CloudModel(
            deviceId: Storage.deviceId,
            model_identifier: "local-only-model",
            endpoint: "https://example.com/v1/chat/completions",
            token: "local-only-token",
        )
        try environment.storage.cloudModelPut(model)
        let recordName = Self.makeRecordName(objectId: model.objectId, tableName: CloudModel.tableName)
        try environment.storage.syncMetadataUpdate([Self.makeMetadata(recordName: recordName)])

        await environment.engine.handleEvent(
            .accountChange(changeType: .signOut(previousUser: CKRecord.ID(recordName: "previous-user"))),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.cloudModel(with: model.id)?.token == "local-only-token")
        #expect(environment.storage.pendingUploadList(tables: [CloudModel.tableName]).map(\.objectId) == [model.objectId])
        #expect(try Self.findMetadata(recordName: recordName, in: environment.storage) == nil)
    }

    @Test
    func accountSwitch_enabledGroup_removesLocalRowsAndPendingUploads() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.models, enabled: true)
        defer { restoreGroup() }

        let model = CloudModel(
            deviceId: Storage.deviceId,
            model_identifier: "synced-model",
            endpoint: "https://example.com/v1/chat/completions",
            token: "synced-token",
        )
        try environment.storage.cloudModelPut(model)

        await environment.engine.handleEvent(
            .accountChange(changeType: .switchAccounts(
                previousUser: CKRecord.ID(recordName: "previous-user"),
                currentUser: CKRecord.ID(recordName: "current-user"),
            )),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.cloudModel(with: model.id) == nil)
        #expect(environment.storage.pendingUploadList(tables: [CloudModel.tableName]).isEmpty)
    }

    // MARK: - Remote record deletions

    @Test
    func remoteMessageDeletion_notifiesConversationOfDeletedMessage() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.conversations, enabled: true)
        defer { restoreGroup() }

        let conversation = environment.storage.conversationMake { _ in }
        let message = environment.storage.makeMessage(with: conversation.id) { _ in }

        let recorder = MessageChangeRecorder()
        let observer = NotificationCenter.default.addObserver(
            forName: SyncEngine.MessageChanged,
            object: nil,
            queue: nil,
        ) { notification in
            guard let info = notification.userInfo?[SyncEngine.MessageNotificationKey] as? MessageNotificationInfo else { return }
            recorder.append(info)
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        let recordID = CKRecord.ID(
            recordName: Self.makeRecordName(objectId: message.objectId, tableName: Message.tableName),
            zoneID: Self.zoneID,
        )
        await environment.engine.handleEvent(
            .fetchedRecordZoneChanges(
                modifications: [],
                deletions: [(recordID: recordID, recordType: Self.recordType)]
            ),
            syncEngine: environment.mock,
        )

        let deletions = recorder.infos.compactMap { $0.deletions[conversation.id] }
        #expect(deletions == [[message.objectId]])
        #expect(environment.storage.listMessages(within: conversation.id).isEmpty)
        #expect(environment.storage.pendingUploadList(tables: [Message.tableName]).isEmpty)
    }

    @Test
    func remoteDeletion_pendingSave_dropsQueuedUploadAndSendsNoRecord() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.memory, enabled: true)
        defer { restoreGroup() }

        let memory = Memory(deviceId: Storage.deviceId, content: "Remember this", conversationId: "conversation-id")
        try environment.storage.insertMemory(memory)
        let queued = try #require(environment.storage.pendingUploadList(tables: [Memory.tableName]).first)

        let separator = SyncEngine.CKRecordSentQueueIdSeparator
        let sentQueueRecordID = CKRecord.ID(
            recordName: "\(queued.id)\(separator)\(memory.objectId)\(separator)\(Storage.deviceId)",
            zoneID: Self.zoneID,
        )
        environment.mock.state.add(pendingRecordZoneChanges: [.saveRecord(sentQueueRecordID)])

        let recordID = CKRecord.ID(
            recordName: Self.makeRecordName(objectId: memory.objectId, tableName: Memory.tableName),
            zoneID: Self.zoneID,
        )
        await environment.engine.handleEvent(
            .fetchedRecordZoneChanges(
                modifications: [],
                deletions: [(recordID: recordID, recordType: Self.recordType)]
            ),
            syncEngine: environment.mock,
        )

        #expect(try environment.storage.getMemory(id: memory.id) == nil)
        #expect(environment.storage.pendingUploadList(tables: [Memory.tableName]).isEmpty)

        let batch = await environment.engine.nextRecordZoneChangeBatch(
            reason: .manual,
            options: CKSyncEngine.SendChangesOptions(),
            syncEngine: environment.mock,
        )
        #expect(batch == nil)
        #expect(!environment.mock.state.pendingRecordZoneChanges.contains(.saveRecord(sentQueueRecordID)))
    }

    // MARK: - Zone deletion

    @Test
    func zoneDeletedByEncryptedDataReset_requeuesLocalRowsAndRecreatesZone() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }

        let (conversation, recordName) = try Self.makeUploadedConversation(in: environment.storage)

        await environment.engine.handleEvent(
            .fetchedDatabaseChanges(modifications: [], deletions: [(zoneID: Self.zoneID, reason: .encryptedDataReset)]),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.pendingUploadList(tables: [Conversation.tableName]).map(\.objectId) == [conversation.objectId])
        #expect(try Self.findMetadata(recordName: recordName, in: environment.storage) == nil)
        #expect(environment.mock.state.pendingDatabaseChanges.contains { change in
            guard case let .saveZone(zone) = change else { return false }
            return zone.zoneID.zoneName == Self.zoneID.zoneName
        })
    }

    @Test
    func zoneDeletedByUser_keepsUploadQueueAndMetadata() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }

        let (_, recordName) = try Self.makeUploadedConversation(in: environment.storage)

        await environment.engine.handleEvent(
            .fetchedDatabaseChanges(modifications: [], deletions: [(zoneID: Self.zoneID, reason: .deleted)]),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.pendingUploadList(tables: [Conversation.tableName]).isEmpty)
        #expect(try Self.findMetadata(recordName: recordName, in: environment.storage) != nil)
        #expect(environment.mock.state.pendingDatabaseChanges.isEmpty)
    }

    @Test
    func saveFailedAfterEncryptedDataReset_requeuesLocalRows() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }

        let (conversation, recordName) = try Self.makeUploadedConversation(in: environment.storage)

        let failedRecord = CKRecord(
            recordType: Self.recordType,
            recordID: CKRecord.ID(recordName: recordName, zoneID: Self.zoneID)
        )
        let error = CKError(.zoneNotFound, userInfo: [CKErrorUserDidResetEncryptedDataKey: true])

        await environment.engine.handleEvent(
            .sentRecordZoneChanges(
                savedRecords: [],
                failedRecordSaves: [(record: failedRecord, error: error)],
                deletedRecordIDs: [],
                failedRecordDeletes: [:],
            ),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.pendingUploadList(tables: [Conversation.tableName]).map(\.objectId) == [conversation.objectId])
        #expect(try Self.findMetadata(recordName: recordName, in: environment.storage) == nil)
        if SyncEngine.isCloudSyncSupported {
            let pendingDatabaseChanges = environment.mock.state.pendingDatabaseChanges
            #expect(pendingDatabaseChanges.contains { change in
                guard case let .saveZone(zone) = change else { return false }
                return zone.zoneID.zoneName == Self.zoneID.zoneName
            })
            #expect(!pendingDatabaseChanges.contains { change in
                guard case .deleteZone = change else { return false }
                return true
            })
        }
    }

    // MARK: - Failed record deletes

    @Test
    func failedDelete_zoneNotFound_dequeuesDelete() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }

        let recordID = Self.makePendingConversationDelete(in: environment.storage)
        environment.mock.state.add(pendingRecordZoneChanges: [.deleteRecord(recordID)])

        await environment.engine.handleEvent(
            .sentRecordZoneChanges(
                savedRecords: [],
                failedRecordSaves: [],
                deletedRecordIDs: [],
                failedRecordDeletes: [recordID: CKError(.zoneNotFound)],
            ),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.pendingUploadList(tables: [Conversation.tableName]).isEmpty)
        if SyncEngine.isCloudSyncSupported {
            #expect(!environment.mock.state.pendingRecordZoneChanges.contains(.deleteRecord(recordID)))
        }
    }

    @Test
    func failedDelete_batchRequestFailed_keepsDeleteQueued() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }

        let recordID = Self.makePendingConversationDelete(in: environment.storage)

        await environment.engine.handleEvent(
            .sentRecordZoneChanges(
                savedRecords: [],
                failedRecordSaves: [],
                deletedRecordIDs: [],
                failedRecordDeletes: [recordID: CKError(.batchRequestFailed)],
            ),
            syncEngine: environment.mock,
        )

        #expect(environment.storage.pendingUploadList(tables: [Conversation.tableName]).first?.changes == .delete)
    }
}

// MARK: - Support

private extension SyncEngineTests {
    final class Environment {
        let directory: URL
        let storage: Storage
        let engine: SyncEngine
        let mock: MockSyncEngine

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SyncEngineTests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

            storage = try Storage.makeForTesting(databaseDir: directory)

            let containerIdentifier = "iCloud.wiki.qaq.flowdown.tests.\(UUID().uuidString)"
            engine = SyncEngine(
                storage: storage,
                containerIdentifier: containerIdentifier,
                mode: .mock,
                automaticallySync: false,
            )
            let container = MockCloudContainer.createContainer(identifier: containerIdentifier)
            mock = MockSyncEngine(
                database: container.privateCloudDatabase,
                parentSyncEngine: engine,
                state: MockSyncEngineState(),
                delegate: engine,
            )
        }

        func tearDown() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    final class MessageChangeRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [MessageNotificationInfo] = []

        var infos: [MessageNotificationInfo] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }

        func append(_ info: MessageNotificationInfo) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(info)
        }
    }

    /// Sets a Sync Scope group and returns a closure that restores the previous value.
    static func setGroup(_ group: SyncPreferences.Group, enabled: Bool) -> () -> Void {
        let previous = SyncPreferences.isGroupEnabled(group)
        SyncPreferences.setGroup(group, enabled: enabled)
        return { SyncPreferences.setGroup(group, enabled: previous) }
    }

    static func makeRecordName(objectId: String, tableName: String) -> String {
        "\(objectId)\(UploadQueue.CKRecordIDSeparator)\(tableName)"
    }

    static func makeMetadata(recordName: String) -> SyncMetadata {
        SyncMetadata(
            record: CKRecord(
                recordType: recordType,
                recordID: CKRecord.ID(recordName: recordName, zoneID: zoneID)
            )
        )
    }

    static func findMetadata(recordName: String, in storage: Storage) throws -> SyncMetadata? {
        try storage.findSyncMetadata(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, recordName: recordName)
    }

    /// A conversation whose upload already finished: no queued upload, one `SyncMetadata` row.
    static func makeUploadedConversation(
        in storage: Storage
    ) throws -> (conversation: Conversation, recordName: String) {
        let conversation = storage.conversationMake { _ in }
        try storage.pendingUploadDequeueDeleted(by: [
            (objectId: conversation.objectId, tableName: Conversation.tableName)
        ])

        let recordName = makeRecordName(objectId: conversation.objectId, tableName: Conversation.tableName)
        try storage.syncMetadataUpdate([makeMetadata(recordName: recordName)])

        #expect(storage.pendingUploadList(tables: [Conversation.tableName]).isEmpty)
        #expect(try findMetadata(recordName: recordName, in: storage) != nil)
        return (conversation, recordName)
    }

    /// A conversation removed on this device, so its latest queued upload is a `.delete`.
    static func makePendingConversationDelete(in storage: Storage) -> CKRecord.ID {
        let conversation = storage.conversationMake { _ in }
        storage.conversationRemove(conversationWith: conversation.id)

        #expect(storage.pendingUploadList(tables: [Conversation.tableName]).first?.changes == .delete)
        return CKRecord.ID(
            recordName: makeRecordName(objectId: conversation.objectId, tableName: Conversation.tableName),
            zoneID: zoneID,
        )
    }
}

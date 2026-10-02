//
//  SyncDeferredDeletionTests.swift
//  FlowDownUnitTests
//

import CloudKit
import Foundation
@testable import Storage
import Testing

/// Covers remote deletions fetched while their Sync Scope group is off: the local table that keeps them,
/// and applying them through the remote-deletion path once the group is turned back on.
/// Serialized because the cases change the shared Sync Scope preferences.
@Suite(.serialized)
struct SyncDeferredDeletionTests {
    private static let zoneID = CKRecordZone.ID(zoneName: "FlowDownSync", ownerName: CKCurrentUserDefaultName)
    private static let recordType: CKRecord.RecordType = "SyncObject"

    // MARK: - Table

    @Test
    func deferredDeletionTable_freshDatabase_savesListsAndRemovesByRecordName() throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let storage = environment.storage

        let serverRecordName = Self.makeRecordName(objectId: "server-id", tableName: ModelContextServer.tableName)
        let memoryRecordName = Self.makeRecordName(objectId: "memory-id", tableName: Memory.tableName)
        try storage.syncDeferredDeletionSave([
            SyncDeferredDeletion(tableName: ModelContextServer.tableName, recordName: serverRecordName),
            SyncDeferredDeletion(tableName: Memory.tableName, recordName: memoryRecordName),
        ])
        // The same deletion fetched again replaces its entry instead of adding a second one.
        try storage.syncDeferredDeletionSave([
            SyncDeferredDeletion(tableName: ModelContextServer.tableName, recordName: serverRecordName),
        ])

        #expect(try storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).map(\.recordName) == [serverRecordName])
        #expect(try storage.syncDeferredDeletionList(tables: []).isEmpty)
        let both = try storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName, Memory.tableName])
        #expect(both.count == 2)
        #expect(Set(both.map(\.recordName)) == [serverRecordName, memoryRecordName])

        try storage.syncDeferredDeletionRemove(recordNames: [serverRecordName])

        #expect(try storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).isEmpty)
        #expect(try storage.syncDeferredDeletionList(tables: [Memory.tableName]).map(\.recordName) == [memoryRecordName])
    }

    // MARK: - Fetching while the group is off

    @Test
    func remoteDeletion_disabledGroup_keepsRowAndDefersDeletion() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: false)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Kept MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)

        await environment.fetch(deletions: [recordName])

        #expect(environment.storage.modelContextServerWith(server.id) != nil)
        #expect(environment.storage.pendingUploadList(tables: [ModelContextServer.tableName]).map(\.objectId) == [server.objectId])
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).map(\.recordName) == [recordName])
    }

    @Test
    func remoteModification_afterDeferredDeletion_dropsDeferredDeletion() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: false)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Re-created MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)
        await environment.fetch(deletions: [recordName])
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).count == 1)

        // The record was re-created after its deletion; the group is still off, so the record itself is dropped.
        await environment.fetch(modifications: [recordName])
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).isEmpty)

        SyncPreferences.setGroup(.mcp, enabled: true)
        await environment.engine.applyDeferredRemoteDeletions(syncEngine: environment.mock)

        #expect(environment.storage.modelContextServerWith(server.id) != nil)
        #expect(environment.storage.pendingUploadList(tables: [ModelContextServer.tableName]).map(\.objectId) == [server.objectId])
    }

    // MARK: - Turning the group back on

    @Test
    func deferredDeletion_groupTurnedBackOn_deletesRowAndPendingUpload() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: false)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Deleted MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)
        try environment.storage.syncMetadataUpdate([Self.makeMetadata(recordName: recordName)])
        await environment.fetch(deletions: [recordName])
        #expect(environment.storage.modelContextServerWith(server.id) != nil)

        SyncPreferences.setGroup(.mcp, enabled: true)
        await environment.engine.applyDeferredRemoteDeletions(syncEngine: environment.mock)

        #expect(environment.storage.modelContextServerWith(server.id) == nil)
        #expect(environment.storage.pendingUploadList(tables: [ModelContextServer.tableName]).isEmpty)
        #expect(try Self.findMetadata(recordName: recordName, in: environment.storage) == nil)
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).isEmpty)
    }

    @Test
    func deferredDeletion_groupStillOff_keepsRowAndEntry() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: false)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Kept MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)
        await environment.fetch(deletions: [recordName])

        await environment.engine.applyDeferredRemoteDeletions(syncEngine: environment.mock)

        #expect(environment.storage.modelContextServerWith(server.id) != nil)
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).map(\.recordName) == [recordName])
    }

    @Test
    func remoteDeletion_enabledGroup_removesDeferredEntry() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: true)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Deleted MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)
        try environment.storage.syncDeferredDeletionSave([
            SyncDeferredDeletion(tableName: ModelContextServer.tableName, recordName: recordName),
        ])

        await environment.fetch(deletions: [recordName])

        #expect(environment.storage.modelContextServerWith(server.id) == nil)
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).isEmpty)
    }

    // MARK: - Account change

    @Test
    func accountSwitch_disabledGroup_clearsDeferredDeletionsAndKeepsRow() async throws {
        let environment = try Environment()
        defer { environment.tearDown() }
        let restoreGroup = Self.setGroup(.mcp, enabled: false)
        defer { restoreGroup() }

        let server = environment.storage.modelContextServerMake { $0.update(\.name, to: "Local MCP") }
        let recordName = Self.makeRecordName(objectId: server.objectId, tableName: ModelContextServer.tableName)
        await environment.fetch(deletions: [recordName])
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).count == 1)

        await environment.engine.handleEvent(
            .accountChange(changeType: .switchAccounts(
                previousUser: CKRecord.ID(recordName: "previous-user"),
                currentUser: CKRecord.ID(recordName: "current-user"),
            )),
            syncEngine: environment.mock,
        )

        // The kept deletion belongs to the previous account, so it must not delete this row later.
        #expect(environment.storage.modelContextServerWith(server.id) != nil)
        #expect(try environment.storage.syncDeferredDeletionList(tables: [ModelContextServer.tableName]).isEmpty)
    }
}

// MARK: - Support

private extension SyncDeferredDeletionTests {
    final class Environment {
        let directory: URL
        let storage: Storage
        let engine: SyncEngine
        let mock: MockSyncEngine

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("SyncDeferredDeletionTests", isDirectory: true)
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

        /// Delivers one fetched batch of record changes, as CKSyncEngine does.
        func fetch(modifications: [String] = [], deletions: [String] = []) async {
            let records = modifications.map { recordName in
                CKRecord(
                    recordType: SyncDeferredDeletionTests.recordType,
                    recordID: SyncDeferredDeletionTests.makeRecordID(recordName)
                )
            }
            let deletedRecords = deletions.map { recordName in
                (
                    recordID: SyncDeferredDeletionTests.makeRecordID(recordName),
                    recordType: SyncDeferredDeletionTests.recordType
                )
            }
            await engine.handleEvent(
                .fetchedRecordZoneChanges(modifications: records, deletions: deletedRecords),
                syncEngine: mock,
            )
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

    static func makeRecordID(_ recordName: String) -> CKRecord.ID {
        CKRecord.ID(recordName: recordName, zoneID: zoneID)
    }

    static func makeMetadata(recordName: String) -> SyncMetadata {
        SyncMetadata(record: CKRecord(recordType: recordType, recordID: makeRecordID(recordName)))
    }

    static func findMetadata(recordName: String, in storage: Storage) throws -> SyncMetadata? {
        try storage.findSyncMetadata(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, recordName: recordName)
    }
}

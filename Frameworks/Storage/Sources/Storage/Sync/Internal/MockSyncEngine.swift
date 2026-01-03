//
//  MockSyncEngine.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit
import OrderedCollections

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockSyncEngine: SyncEngineProtocol {
    package let database: MockCloudDatabase
    package let parentSyncEngine: SyncEngine
    package let _state: LockIsolated<MockSyncEngineState>
    package let _fetchChangesScopes = LockIsolated<[CKSyncEngine.FetchChangesOptions.Scope]>([])
    package let _delegate: LockIsolated<(any SyncEngineDelegate)?>
    package var automaticallySync: Bool {
        get {
            scheduleTask.withValue { task in
                task != nil
            }
        }
        set {
            scheduleTask.withValue { task in
                if !newValue {
                    task?.cancel()
                    task = nil
                    return
                }

                if task != nil {
                    return
                }

                task = Task {
                    while true {
                        try await Task.sleep(nanoseconds: 10 * 1_000_000_000)
                        try await self.autoFetchChanges()
                        try await self.autoSendChanges()
                    }
                }
            }
        }
    }

    let scheduleTask: LockIsolated<Task<Void, Error>?> = .init(nil)

    package var description: String {
        "\(type(of: self))"
    }

    package var scope: CKDatabase.Scope {
        database.databaseScope
    }

    package var state: MockSyncEngineState {
        _state.withValue(\.self)
    }

    package var delegate: (any SyncEngineDelegate)? {
        _delegate.withValue(\.self)
    }

    package init(database: MockCloudDatabase, parentSyncEngine: SyncEngine, state: MockSyncEngineState, delegate: any SyncEngineDelegate) {
        self.database = database
        self.parentSyncEngine = parentSyncEngine
        _state = LockIsolated(state)
        _delegate = LockIsolated(delegate)
    }

    private func processPendingDatabaseChanges(reason: CKSyncEngine.SyncReason, options _: CKSyncEngine.SendChangesOptions) async throws {
        Logger.syncEngine.infoFile("Will Processing database changes by reason: \(reason)")
        let pendingDatabaseChanges = state.pendingDatabaseChanges
        guard !pendingDatabaseChanges.isEmpty else {
            Logger.syncEngine.infoFile("Processing empty set of database changes.")
            return
        }

        var recordZonesToSave: [CKRecordZone] = []
        var recordZoneIDsToDelete: [CKRecordZone.ID] = []
        for change in pendingDatabaseChanges {
            switch change {
            case let .saveZone(zone):
                recordZonesToSave.append(zone)
            case let .deleteZone(zoneId):
                recordZoneIDsToDelete.append(zoneId)
            default:
                break
            }
        }

        if recordZonesToSave.isEmpty, recordZoneIDsToDelete.isEmpty {
            return
        }

        try Task.checkCancellation()

        Logger.syncEngine.infoFile("will sent saveZone: \(recordZonesToSave) deleteZone: \(recordZoneIDsToDelete)")

        let (saveResults, deleteResults) = try await database.modifyRecordZones(saving: recordZonesToSave, deleting: recordZoneIDsToDelete)

        if saveResults.isEmpty, deleteResults.isEmpty {
            return
        }

        try Task.checkCancellation()

        var savedZones: [CKRecordZone] = []
        var failedZoneSaves: [(zone: CKRecordZone, error: CKError)] = []
        var deletedZoneIDs: [CKRecordZone.ID] = []
        var failedZoneDeletes: [CKRecordZone.ID: CKError] = [:]
        for (zoneID, result) in saveResults {
            switch result {
            case let .success(zone):
                savedZones.append(zone)
            case let .failure(error as CKError):
                guard let zone = recordZonesToSave.first(where: { $0.zoneID == zoneID })
                else { fatalError("\(zoneID.debugDescription) not found in pending changes") }
                failedZoneSaves.append((zone: zone, error: error))
            case .failure:
                fatalError("Mocks should only raise 'CKError' values.")
            }
        }
        for (zoneID, result) in deleteResults {
            switch result {
            case .success:
                deletedZoneIDs.append(zoneID)
            case let .failure(error as CKError):
                failedZoneDeletes[zoneID] = error
            case .failure:
                fatalError("Mocks should only raise 'CKError' values.")
            }
        }

        state.remove(pendingDatabaseChanges: savedZones.map { .saveZone($0) })
        state.remove(pendingDatabaseChanges: deletedZoneIDs.map { .deleteZone($0) })

        let event = SyncEngine.Event.sentDatabaseChanges(
            savedZones: savedZones,
            failedZoneSaves: failedZoneSaves,
            deletedZoneIDs: deletedZoneIDs,
            failedZoneDeletes: failedZoneDeletes,
        )

        await parentSyncEngine.handleEvent(event, syncEngine: self)
    }

    private func processPendingRecordZoneChanges(reason: CKSyncEngine.SyncReason, options: CKSyncEngine.SendChangesOptions) async throws {
        Logger.syncEngine.infoFile("Will Processing record zone changes by reason: \(reason)")
        let pendingRecordZoneChanges = state.pendingRecordZoneChanges
        guard !pendingRecordZoneChanges.isEmpty else {
            Logger.syncEngine.infoFile("Processing empty set of record zone changes.")
            return
        }

        guard let delegate else { return }

        let batch = await delegate.nextRecordZoneChangeBatch(reason: reason, options: options, syncEngine: self)
        guard let batch else {
            Logger.syncEngine.infoFile("Processing empty batch of record zone changes.")
            return
        }

        try Task.checkCancellation()

        let (saveResults, deleteResults) = try await database.modifyRecords(
            saving: batch.recordsToSave,
            deleting: batch.recordIDsToDelete,
            savePolicy: .ifServerRecordUnchanged,
            atomically: batch.atomicByZone,
        )

        if saveResults.isEmpty, deleteResults.isEmpty {
            return
        }

        try Task.checkCancellation()

        var savedRecords: [CKRecord] = []
        var failedRecordSaves: [(record: CKRecord, error: CKError)] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var failedRecordDeletes: [CKRecord.ID: CKError] = [:]
        for (recordID, result) in saveResults {
            switch result {
            case let .success(record):
                savedRecords.append(record)
            case let .failure(error as CKError):
                guard let record = batch.recordsToSave.first(where: { $0.recordID == recordID })
                else { fatalError("\(recordID.debugDescription) not found in pending changes") }
                failedRecordSaves.append((record: record, error: error))
            case .failure:
                fatalError("Mocks should only raise 'CKError' values.")
            }
        }
        for (recordID, result) in deleteResults {
            switch result {
            case .success:
                deletedRecordIDs.append(recordID)
            case let .failure(error as CKError):
                failedRecordDeletes[recordID] = error
            case .failure:
                fatalError("Mocks should only raise 'CKError' values.")
            }
        }

        state.remove(
            pendingRecordZoneChanges: savedRecords.compactMap {
                guard let sentQueueId = $0.sentQueueId else {
                    return nil
                }

                return .saveRecord(CKRecord.ID(recordName: sentQueueId, zoneID: $0.recordID.zoneID))
            },
        )

        state.remove(
            pendingRecordZoneChanges: deletedRecordIDs.map { .deleteRecord($0) },
        )

        let event = SyncEngine.Event.sentRecordZoneChanges(
            savedRecords: savedRecords,
            failedRecordSaves: failedRecordSaves,
            deletedRecordIDs: deletedRecordIDs,
            failedRecordDeletes: failedRecordDeletes,
        )

        await parentSyncEngine.handleEvent(event, syncEngine: self)
    }

    private func autoFetchChanges() async throws {}

    private func autoSendChanges() async throws {
        try await processPendingDatabaseChanges(reason: .scheduled, options: .init())
        try await processPendingRecordZoneChanges(reason: .scheduled, options: .init())
    }

    package func cancelOperations() async {}

    package func performingFetchChanges() async throws {
        guard let delegate else {
            try await performingFetchChanges(.init())
            return
        }

        let options = await delegate.nextFetchChangesOptions(reason: .manual, options: .init(), syncEngine: self)
        try await performingFetchChanges(options)
    }

    package func performingFetchChanges(_: CKSyncEngine.FetchChangesOptions) async throws {}

    package func nextRecordZoneChangeBatch(recordsToSave _: [CKRecord], recordIDsToDelete _: [CKRecord.ID], atomicByZone _: Bool, syncEngine _: any SyncEngineProtocol) async -> CKSyncEngine.RecordZoneChangeBatch? {
        nil
    }

    package func performingSendChanges() async throws {
        try await performingSendChanges(.init())
    }

    package func performingSendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws {
        try await processPendingDatabaseChanges(reason: .manual, options: options)
        try await processPendingRecordZoneChanges(reason: .manual, options: options)
    }
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package final class MockSyncEngineState: CKSyncEngineStateProtocol {
    package let _pendingRecordZoneChanges = LockIsolated<
        OrderedSet<CKSyncEngine.PendingRecordZoneChange>,
    >([])
    package let _pendingDatabaseChanges = LockIsolated<
        OrderedSet<CKSyncEngine.PendingDatabaseChange>,
    >([])

    package var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] {
        _pendingRecordZoneChanges.withValue { Array($0) }
    }

    package var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] {
        _pendingDatabaseChanges.withValue { Array($0) }
    }

    package func removePendingChanges() {
        _pendingDatabaseChanges.withValue { $0.removeAll() }
        _pendingRecordZoneChanges.withValue { $0.removeAll() }
    }

    package func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
        _pendingRecordZoneChanges.withValue {
            $0.append(contentsOf: pendingRecordZoneChanges)
        }
    }

    package func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange]) {
        _pendingRecordZoneChanges.withValue {
            $0.subtract(pendingRecordZoneChanges)
        }
    }

    package func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
        _pendingDatabaseChanges.withValue {
            $0.append(contentsOf: pendingDatabaseChanges)
        }
    }

    package func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange]) {
        _pendingDatabaseChanges.withValue {
            $0.subtract(pendingDatabaseChanges)
        }
    }
}

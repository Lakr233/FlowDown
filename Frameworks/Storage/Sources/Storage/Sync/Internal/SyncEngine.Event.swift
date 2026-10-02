//
//  SyncEngine.Event.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package extension SyncEngine {
    enum Event: CustomStringConvertible {
        case stateUpdate(stateSerialization: CKSyncEngine.State.Serialization)
        case accountChange(changeType: CKSyncEngine.Event.AccountChange.ChangeType)
        case fetchedDatabaseChanges(
            modifications: [CKRecordZone.ID],
            deletions: [(zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason)],
        )
        case fetchedRecordZoneChanges(
            modifications: [CKRecord],
            deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)],
        )
        case sentDatabaseChanges(
            savedZones: [CKRecordZone],
            failedZoneSaves: [(zone: CKRecordZone, error: CKError)],
            deletedZoneIDs: [CKRecordZone.ID],
            failedZoneDeletes: [CKRecordZone.ID: CKError],
        )
        case sentRecordZoneChanges(
            savedRecords: [CKRecord],
            failedRecordSaves: [(record: CKRecord, error: CKError)],
            deletedRecordIDs: [CKRecord.ID],
            failedRecordDeletes: [CKRecord.ID: CKError],
        )
        case willFetchChanges
        case willFetchRecordZoneChanges
        case didFetchChanges
        case didFetchRecordZoneChanges
        case willSendChanges
        case didSendChanges

        init?(_ event: CKSyncEngine.Event) {
            switch event {
            case let .stateUpdate(event):
                self = .stateUpdate(stateSerialization: event.stateSerialization)
            case let .accountChange(event):
                self = .accountChange(changeType: event.changeType)
            case let .fetchedDatabaseChanges(event):
                self = .fetchedDatabaseChanges(
                    modifications: event.modifications.map(\.zoneID),
                    deletions: event.deletions.map { (zoneID: $0.zoneID, reason: $0.reason) },
                )
            case let .fetchedRecordZoneChanges(event):
                self = .fetchedRecordZoneChanges(
                    modifications: event.modifications.map(\.record),
                    deletions: event.deletions.map {
                        (recordID: $0.recordID, recordType: $0.recordType)
                    },
                )
            case let .sentDatabaseChanges(event):
                self = .sentDatabaseChanges(
                    savedZones: event.savedZones,
                    failedZoneSaves: event.failedZoneSaves.map { (zone: $0.zone, error: $0.error) },
                    deletedZoneIDs: event.deletedZoneIDs,
                    failedZoneDeletes: event.failedZoneDeletes,
                )
            case let .sentRecordZoneChanges(event):
                self = .sentRecordZoneChanges(
                    savedRecords: event.savedRecords,
                    failedRecordSaves: event.failedRecordSaves.map { (record: $0.record, error: $0.error) },
                    deletedRecordIDs: event.deletedRecordIDs,
                    failedRecordDeletes: event.failedRecordDeletes,
                )
            case .willFetchChanges:
                self = .willFetchChanges
            case .willFetchRecordZoneChanges:
                self = .willFetchRecordZoneChanges
            case .didFetchChanges:
                self = .didFetchChanges
            case .didFetchRecordZoneChanges:
                self = .didFetchRecordZoneChanges
            case .willSendChanges:
                self = .willSendChanges
            case .didSendChanges:
                self = .didSendChanges
            @unknown default:
                return nil
            }
        }

        package var description: String {
            switch self {
            case .stateUpdate: "stateUpdate"
            case .accountChange: "accountChange"
            case .fetchedDatabaseChanges: "fetchedDatabaseChanges"
            case .fetchedRecordZoneChanges: "fetchedRecordZoneChanges"
            case .sentDatabaseChanges: "sentDatabaseChanges"
            case .sentRecordZoneChanges: "sentRecordZoneChanges"
            case .willFetchChanges: "willFetchChanges"
            case .willFetchRecordZoneChanges: "willFetchRecordZoneChanges"
            case .didFetchRecordZoneChanges: "didFetchRecordZoneChanges"
            case .didFetchChanges: "didFetchChanges"
            case .willSendChanges: "willSendChanges"
            case .didSendChanges: "didSendChanges"
            }
        }
    }
}

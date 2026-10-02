//
//  CloudDatabase.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

package protocol CloudDatabase: AnyObject, Hashable, Sendable {
    var databaseScope: CKDatabase.Scope { get }

    func allRecordZones() async throws -> [CKRecordZone]

    func record(for recordID: CKRecord.ID) async throws -> CKRecord

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func records(
        for ids: [CKRecord.ID],
        desiredKeys: [CKRecord.FieldKey]?,
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
        savePolicy: CKModifyRecordsOperation.RecordSavePolicy,
        atomically: Bool,
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>],
    )

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func modifyRecordZones(
        saving recordZonesToSave: [CKRecordZone],
        deleting recordZoneIDsToDelete: [CKRecordZone.ID],
    ) async throws -> (
        saveResults: [CKRecordZone.ID: Result<CKRecordZone, any Error>],
        deleteResults: [CKRecordZone.ID: Result<Void, any Error>],
    )
}

package extension CloudDatabase {
    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func modifyRecords(
        saving recordsToSave: [CKRecord],
        deleting recordIDsToDelete: [CKRecord.ID],
    ) async throws -> (
        saveResults: [CKRecord.ID: Result<CKRecord, any Error>],
        deleteResults: [CKRecord.ID: Result<Void, any Error>],
    ) {
        try await modifyRecords(
            saving: recordsToSave,
            deleting: recordIDsToDelete,
            savePolicy: .ifServerRecordUnchanged,
            atomically: true,
        )
    }

    @available(macOS 12, iOS 15, tvOS 15, watchOS 8, *)
    func records(
        for ids: [CKRecord.ID],
    ) async throws -> [CKRecord.ID: Result<CKRecord, any Error>] {
        try await records(for: ids, desiredKeys: nil)
    }
}

extension CKDatabase: CloudDatabase {}

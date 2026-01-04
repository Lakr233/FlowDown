//
//  SyncEngineProtocol.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol SyncEngineDelegate: AnyObject, Sendable {
    func handleEvent(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) async
    func nextRecordZoneChangeBatch(
        reason: CKSyncEngine.SyncReason,
        options: CKSyncEngine.SendChangesOptions,
        syncEngine: any SyncEngineProtocol,
    ) async -> CKSyncEngine.RecordZoneChangeBatch?

    func nextFetchChangesOptions(
        reason: CKSyncEngine.SyncReason,
        options: CKSyncEngine.FetchChangesOptions,
        syncEngine: any SyncEngineProtocol,
    ) async -> CKSyncEngine.FetchChangesOptions
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
extension SyncEngineDelegate {
    func nextFetchChangesOptions(
        reason _: CKSyncEngine.SyncReason,
        options _: CKSyncEngine.FetchChangesOptions,
        syncEngine _: any SyncEngineProtocol,
    ) async -> CKSyncEngine.FetchChangesOptions {
        CKSyncEngine.FetchChangesOptions()
    }
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol SyncEngineProtocol<Database, State>: AnyObject, Sendable, CustomStringConvertible {
    associatedtype State: CKSyncEngineStateProtocol
    associatedtype Database: CloudDatabase

    var database: Database { get }
    var state: State { get }

    func cancelOperations() async
    func performingFetchChanges() async throws
    func performingFetchChanges(_ options: CKSyncEngine.FetchChangesOptions) async throws
    func performingSendChanges() async throws
    func performingSendChanges(_ options: CKSyncEngine.SendChangesOptions) async throws
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
package protocol CKSyncEngineStateProtocol: Sendable {
    var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { get }
    var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] { get }
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
    func remove(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine: SyncEngineProtocol {
    package func performingFetchChanges() async throws {
        try await fetchChanges()
    }

    package func performingFetchChanges(_ options: FetchChangesOptions) async throws {
        try await fetchChanges(options)
    }

    package func performingSendChanges() async throws {
        try await sendChanges()
    }

    package func performingSendChanges(_ options: SendChangesOptions) async throws {
        try await sendChanges(options)
    }
}

@available(iOS 17, macCatalyst 17, macOS 14, tvOS 17, watchOS 10, *)
extension CKSyncEngine.State: CKSyncEngineStateProtocol {}

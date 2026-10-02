//
//  SyncEngine+CKSyncEngineDelegate.swift
//  Storage
//

import CloudKit

// MARK: - CKSyncEngineDelegate

@available(iOS 17, macCatalyst 17, *)
extension SyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let event = SyncEngine.Event(event) else {
            return
        }

        await handleEvent(event, syncEngine: syncEngine)
    }

    public func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await nextRecordZoneChangeBatch(reason: context.reason, options: context.options, syncEngine: syncEngine)
    }

    public func nextFetchChangesOptions(
        _ context: CKSyncEngine.FetchChangesContext,
        syncEngine _: CKSyncEngine
    ) async -> CKSyncEngine.FetchChangesOptions {
        let options = context.options
        Logger.syncEngine.infoFile("Next fetch by reason: \(context.reason)")
        return options
    }
}

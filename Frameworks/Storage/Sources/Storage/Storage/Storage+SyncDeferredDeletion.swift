//
//  Storage+SyncDeferredDeletion.swift
//  Storage
//

import Foundation
import WCDBSwift

package extension Storage {
    /// Keeps remote deletions whose Sync Scope group is turned off, replacing any earlier entry for the same record.
    func syncDeferredDeletionSave(_ deletions: [SyncDeferredDeletion]) throws {
        guard !deletions.isEmpty else {
            return
        }
        try db.insertOrReplace(deletions, intoTable: SyncDeferredDeletion.tableName)
    }

    /// Lists the deferred remote deletions of the given tables.
    func syncDeferredDeletionList(tables: [String]) throws -> [SyncDeferredDeletion] {
        guard !tables.isEmpty else {
            return []
        }
        return try db.getObjects(
            fromTable: SyncDeferredDeletion.tableName,
            where: SyncDeferredDeletion.Properties.tableName.in(tables),
        )
    }

    /// Removes deferred remote deletions once the deletion has been applied.
    func syncDeferredDeletionRemove(recordNames: [String], handle: Handle? = nil) throws {
        guard !recordNames.isEmpty else {
            return
        }
        if let handle {
            try handle.delete(
                fromTable: SyncDeferredDeletion.tableName,
                where: SyncDeferredDeletion.Properties.recordName.in(recordNames),
            )
        } else {
            try db.delete(
                fromTable: SyncDeferredDeletion.tableName,
                where: SyncDeferredDeletion.Properties.recordName.in(recordNames),
            )
        }
    }
}

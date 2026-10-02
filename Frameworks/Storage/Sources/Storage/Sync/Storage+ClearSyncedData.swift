//
//  Storage+ClearSyncedData.swift
//  Storage
//

import Foundation
import WCDBSwift

extension Storage {
    /// Clears the synced tables after the iCloud account signs out or switches.
    ///
    /// Tables that are not listed, and their pending uploads, stay on this device.
    /// All `SyncMetadata` and `SyncDeferredDeletion` rows are removed because they belong to the previous account.
    /// - Parameter tables: Data tables to clear, usually `SyncPreferences.enabledTables()`.
    func clearLocalData(tables: [String]) throws {
        try db.run(transaction: {
            for table in tables {
                try $0.delete(fromTable: table)
            }

            if !tables.isEmpty {
                try $0.delete(
                    fromTable: UploadQueue.tableName,
                    where: UploadQueue.Properties.tableName.in(tables),
                )
            }

            try $0.delete(fromTable: SyncMetadata.tableName)
            try $0.delete(fromTable: SyncDeferredDeletion.tableName)

            let row = try $0.getRow(on: UploadQueue.Properties.id.count(), fromTable: UploadQueue.tableName)
            guard row.first?.int64Value == 0 else { return }

            let nameColumn = WCDBSwift.Column(named: "name")
            let seqColumn = WCDBSwift.Column(named: "seq")
            let updateTableSequence = StatementUpdate()
                .update(table: "sqlite_sequence")
                .set(seqColumn)
                .to(0)
                .where(nameColumn == UploadQueue.tableName)

            try $0.exec(updateTableSequence)
        })
    }
}

//
//  SyncDeferredDeletion.swift
//  Storage
//

import Foundation
import WCDBSwift

/// A remote deletion fetched while its Sync Scope group was turned off.
///
/// CloudKit moves the change token past a fetched deletion and never delivers it again,
/// so it is kept here and applied when the group is turned back on.
/// The table stays on this device and is never synced.
package final class SyncDeferredDeletion: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "SyncDeferredDeletion"

    package var id: String {
        recordName
    }

    /// Table of the deleted object, which decides its Sync Scope group.
    package var tableName: String = .init()
    /// CloudKit record name of the deleted object.
    package var recordName: String = .init()

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = SyncDeferredDeletion
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(tableName, isNotNull: true)
            BindColumnConstraint(recordName, isNotNull: true, isUnique: true)

            BindIndex(tableName, namedWith: "_tableNameIndex")
        }

        case tableName
        case recordName
    }

    package convenience init(tableName: String, recordName: String) {
        self.init()
        self.tableName = tableName
        self.recordName = recordName
    }
}

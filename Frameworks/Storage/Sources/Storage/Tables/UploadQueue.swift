//
//  UploadQueue.swift
//  Storage
//
//  Created by king on 2025/10/13.
//

import Foundation
import WCDBSwift

package final class UploadQueue: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "UploadQueue"
    /// Upload attempts after which a queue entry is no longer retried.
    static let maxFailCount = 100
    /// 队列ID
    package var id: Int64 = .init()
    /// 源数据表名
    package var tableName: String = .init()
    /// 源数据ID
    package var objectId: String = .init()
    /// 源数据设备ID
    package var deviceId: String = .init()
    /// 源数据创建时间
    package var creation: Date = .now
    /// 源数据修改时间
    package var modified: Date = .now
    /// 变化类型
    package var changes: UploadQueue.Changes = .insert
    /// 上传状态
    package var state: UploadQueue.State = .pending
    /// 上传失败次数
    package var failCount: Int = 0

    /// 关联的真实对象
    package var realObject: (any Syncable)?

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = UploadQueue
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(.id, isPrimary: true, isAutoIncrement: true)

            BindColumnConstraint(tableName, isNotNull: true)
            BindColumnConstraint(objectId, isNotNull: true)
            BindColumnConstraint(deviceId, isNotNull: true)
            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(changes, isNotNull: true)
            BindColumnConstraint(state, isNotNull: true)
            BindColumnConstraint(failCount, isNotNull: true)

            BindIndex(state, namedWith: "_stateIndex")
            BindIndex(tableName, state, namedWith: "_tableNameAndStateIndex")
            BindIndex(tableName, objectId, namedWith: "_tableNameANDObjectIdIndex")
        }

        case id
        case tableName
        case objectId
        case deviceId
        case creation
        case modified
        case changes
        case state
        case failCount
    }

    package var isAutoIncrement: Bool = true
    package var lastInsertedRowID: Int64 = .min
}

package extension UploadQueue {
    enum Changes: Int, Codable, Equatable, ColumnCodable, ExpressionConvertible {
        case insert = 0
        case update = 1
        case delete = 2

        package init?(with value: WCDBSwift.Value) {
            self.init(rawValue: value.intValue)
        }

        package func archivedValue() -> WCDBSwift.Value {
            Value(Int32(rawValue))
        }

        package static var columnType: WCDBSwift.ColumnType {
            .integer32
        }

        package func asExpression() -> WCDBSwift.Expression {
            WCDBSwift.Expression(integerLiteral: rawValue)
        }
    }
}

package extension UploadQueue {
    enum State: Int, Codable, Equatable, ColumnCodable, ExpressionConvertible {
        case pending = 0
        case uploading = 1
        case finish = 2
        case failed = 3

        package init?(with value: WCDBSwift.Value) {
            self.init(rawValue: value.intValue)
        }

        package func archivedValue() -> WCDBSwift.Value {
            Value(Int32(rawValue))
        }

        package static var columnType: WCDBSwift.ColumnType {
            .integer32
        }

        package func asExpression() -> WCDBSwift.Expression {
            WCDBSwift.Expression(integerLiteral: rawValue)
        }
    }
}

package extension UploadQueue {
    convenience init<T: Syncable>(source: T, changes: Changes) throws {
        self.init()
        objectId = source.objectId
        deviceId = source.deviceId
        tableName = T.tableName
        creation = source.creation
        modified = source.modified
        self.changes = changes
    }
}

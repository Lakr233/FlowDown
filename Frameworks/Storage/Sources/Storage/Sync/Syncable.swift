//
//  Syncable.swift
//  Storage
//
//  Created by king on 2025/10/11.
//

import Foundation
import WCDBSwift

package protocol Syncable: TableDecodable {
    /// 每条记录的唯一标识
    var objectId: String { get }

    /// 创建时间
    var creation: Date { get }

    /// 最后修改时间
    var modified: Date { get }

    /// 删除标记
    var removed: Bool { get }

    /// Sets the last modified time.
    func markModified(_ date: Date)

    /// 用于标识来源设备
    var deviceId: String { get }

    /// 该对象所属的表名
    static var tableName: String { get }

    /// 序列化为上传 payload
    func encodePayload() throws -> Data

    /// 从 payload 恢复对象
    static func decodePayload(_ data: Data) throws -> Self
}

//
//  CKRecord+Extension.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

package extension CKRecord.FieldKey {
    static let sentQueueId = "sentQueueId"
    static let tableName = "tableName"
    static let createByDeviceId = "createByDeviceId"
    static let lastModifiedByDeviceId = "lastModifiedByDeviceId"
    static let payload = "payload"
    static let payloadAsset = "payloadAsset"
    static let lastModifiedMilliseconds = "lastModifiedMilliseconds"
}

package extension CKRecord {
    var _recordChangeTag: String? {
        get { self[#function] }
        set { self[#function] = newValue }
    }

    /// 发送队列ID，仅对当前设备有效
    var sentQueueId: String? {
        get { self[.sentQueueId] as? String }
        set { self[.sentQueueId] = newValue }
    }

    /// 记录首次创建的设备ID
    var createByDeviceId: String? {
        get { self[.createByDeviceId] as? String }
        set { self[.createByDeviceId] = newValue }
    }

    /// 记录最后一次修改的设备ID
    var lastModifiedByDeviceId: String? {
        get { self[.lastModifiedByDeviceId] as? String }
        set { self[.lastModifiedByDeviceId] = newValue }
    }

    /// 记录最后一次修改时间戳，避免直接使用 Date 比较有精度问题
    var lastModifiedMilliseconds: Int64 {
        get { self[.lastModifiedMilliseconds] as? Int64 ?? 0 }
        set { self[.lastModifiedMilliseconds] = newValue }
    }

    var payloadData: Data? {
        if let payload = encryptedValues[.payload] as? Data {
            return payload
        }

        if let asset = self[.payloadAsset] as? CKAsset, let fileURL = asset.fileURL {
            let data = try? Data(contentsOf: fileURL)
            return data
        }

        return nil
    }

    func clearTemporaryAssets(prefix: URL) {
        guard let asset = self[.payloadAsset] as? CKAsset, let fileURL = asset.fileURL else { return }
        guard fileURL.path().hasPrefix(prefix.path()) else {
            return
        }

        try? FileManager.default.removeItem(at: fileURL)
    }
}

package extension UploadQueue {
    static let CKRecordIDSeparator: String = ":"

    /// 记录对应的ID， 格式为 '353F4781-F01D-4029-ABA4-4518D9397BC0:TableName'
    var ckRecordID: String {
        "\(objectId)\(UploadQueue.CKRecordIDSeparator)\(tableName)"
    }

    /// 解析记录ID
    /// - Parameter recordID: 记录ID
    /// - Returns: 返回原始记录唯一ID和对应的表名
    static func parseCKRecordID(_ recordID: String) -> (objectId: String, tableName: String)? {
        let splits = recordID.split(separator: UploadQueue.CKRecordIDSeparator)
        guard splits.count == 2 else {
            return nil
        }
        return (String(splits[0]), String(splits[1]))
    }
}

extension CKRecord: @unchecked @retroactive Sendable {}

extension CKRecordZone: @unchecked @retroactive Sendable {}

extension CKRecordZone.ID: @unchecked @retroactive Sendable {}

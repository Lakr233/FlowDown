//
//  Storage+UploadQueue.swift
//  Storage
//
//  Created by king on 2025/10/12.
//

import Compression
import Foundation
import WCDBSwift

private enum SyncPayloadCoder {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.dataEncodingStrategy = .base64
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        decoder.dataDecodingStrategy = .base64
        return decoder
    }()
}

// MARK: - Sync

struct FlowDownPayloadHeader {
    static let CompressionThreshold: Int = 1024
    static let magic: [UInt8] = [0x46, 0x6C, 0x6F, 0x77, 0x44, 0x6F, 0x77, 0x6E] // "FlowDown"
    static let version: UInt8 = 1

    enum Algorithm: UInt8, CaseIterable {
        case none = 0
        case lzfse = 1
        case zlib = 2
        case lz4 = 3
        case lzma = 4

        var compressionAlgorithm: compression_algorithm? {
            switch self {
            case .lzfse: COMPRESSION_LZFSE
            case .zlib: COMPRESSION_ZLIB
            case .lz4: COMPRESSION_LZ4
            case .lzma: COMPRESSION_LZMA
            case .none: nil
            }
        }
    }

    var compressionAlgorithm: Algorithm

    /// 序列化为 Data
    func encode() -> Data {
        var data = Data(FlowDownPayloadHeader.magic)
        data.append(FlowDownPayloadHeader.version)
        data.append(compressionAlgorithm.rawValue)
        return data
    }

    /// 从 Data 解析 header
    static func decode(from data: Data) throws -> (header: FlowDownPayloadHeader, payloadOffset: Int) {
        guard data.count >= 10 else {
            throw NSError(domain: "CompressionHeader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Data too short"])
        }

        let magic = Array(data[0 ..< 8])
        guard magic == FlowDownPayloadHeader.magic else {
            throw NSError(domain: "CompressionHeader", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid magic number"])
        }

        let version = data[8]
        guard version == FlowDownPayloadHeader.version else {
            throw NSError(domain: "CompressionHeader", code: -3, userInfo: [NSLocalizedDescriptionKey: "Unsupported version"])
        }

        let algorithmByte = data[9]
        guard let alg = Algorithm(rawValue: algorithmByte) else {
            throw NSError(domain: "CompressionHeader", code: -4, userInfo: [NSLocalizedDescriptionKey: "Unknown algorithm"])
        }

        return (FlowDownPayloadHeader(compressionAlgorithm: alg), 10)
    }
}

extension Storage {
    static func encodePayloadSyncable(_ value: some Codable) throws -> Data {
        let plistData = try SyncPayloadCoder.encoder.encode(value)

        var header = FlowDownPayloadHeader(compressionAlgorithm: FlowDownPayloadHeader.Algorithm.none)
        if plistData.count >= FlowDownPayloadHeader.CompressionThreshold, let compressed = plistData.compressed(using: COMPRESSION_LZFSE) {
            header.compressionAlgorithm = FlowDownPayloadHeader.Algorithm.lzfse
            let headerData = header.encode()
            var result = Data(headerData)
            result.append(compressed)
            return result
        } else {
            let headerData = header.encode()
            var result = Data(headerData)
            result.append(plistData)
            return result
        }
    }

    static func decodePayloadSyncable<T: Codable>(_: T.Type, _ data: Data) throws -> T {
        guard !data.isEmpty else {
            throw NSError(domain: "Storage.decodePayloadSyncable", code: -100, userInfo: [NSLocalizedDescriptionKey: "Empty data"])
        }

        let (header, offset) = try FlowDownPayloadHeader.decode(from: data)
        let payload = data.subdata(in: offset ..< data.count)

        let plistData: Data
        if let alg = header.compressionAlgorithm.compressionAlgorithm {
            guard let decompressed = payload.decompressed(using: alg) else {
                throw NSError(domain: "Storage.decodePayloadSyncable", code: -2, userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
            }
            plistData = decompressed
        } else {
            plistData = payload
        }

        return try SyncPayloadCoder.decoder.decode(T.self, from: plistData)
    }
}

extension CloudModel: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: CloudModel.Properties.objectId.asProperty(), creation: CloudModel.Properties.creation.asProperty(), modified: CloudModel.Properties.modified.asProperty(), removed: CloudModel.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension ModelContextServer: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: ModelContextServer.Properties.objectId.asProperty(), creation: ModelContextServer.Properties.creation.asProperty(), modified: ModelContextServer.Properties.modified.asProperty(), removed: ModelContextServer.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Memory: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Memory.Properties.objectId.asProperty(), creation: Memory.Properties.creation.asProperty(), modified: Memory.Properties.modified.asProperty(), removed: Memory.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Conversation: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Conversation.Properties.objectId.asProperty(), creation: Conversation.Properties.creation.asProperty(), modified: Conversation.Properties.modified.asProperty(), removed: Conversation.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Message: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Message.Properties.objectId.asProperty(), creation: Message.Properties.creation.asProperty(), modified: Message.Properties.modified.asProperty(), removed: Message.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Attachment: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Attachment.Properties.objectId.asProperty(), creation: Attachment.Properties.creation.asProperty(), modified: Attachment.Properties.modified.asProperty(), removed: Attachment.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension ChatTemplateRecord: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: ChatTemplateRecord.Properties.objectId.asProperty(), creation: ChatTemplateRecord.Properties.creation.asProperty(), modified: ChatTemplateRecord.Properties.modified.asProperty(), removed: ChatTemplateRecord.Properties.removed.asProperty())

    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

package extension Storage {
    struct DiffSyncableResult<T: Syncable> {
        /// 新增的
        package let insert: [T]
        /// 更新的
        package let updated: [T]
        /// 删除的
        package let deleted: [T]

        package var isEmpty: Bool {
            insert.isEmpty && updated.isEmpty && deleted.isEmpty
        }

        package init(insert: [T] = [], updated: [T] = [], deleted: [T] = []) {
            self.insert = insert
            self.updated = updated
            self.deleted = deleted
        }

        package func insertOrReplace() -> [T] {
            insert + updated
        }
    }

    /// 根据本地数据库现有数据，区分新增/更新/删除对象
    /// - Parameters:
    ///   - objects: 需要处理的对象数组
    ///   - handle: 可选 WCDB Handle
    /// - Returns: 三个数组：新增、更新、删除
    func diffSyncable<T: Syncable & SyncQueryable>(
        objects: [T],
        handle: Handle? = nil,
    ) throws -> DiffSyncableResult<T> {
        guard !objects.isEmpty else {
            return DiffSyncableResult()
        }

        // 1️⃣ 获取所有 objectId
        let objectIds = objects.map(\.objectId)

        // 2️⃣ 查询本地对应的对象
        let existsObjects: [T] = if let handle {
            try handle.getObjects(fromTable: T.tableName, where: T.SyncQuery.objectId.in(objectIds))
        } else {
            try db.getObjects(fromTable: T.tableName, where: T.SyncQuery.objectId.in(objectIds))
        }

        // 构建本地字典：objectId -> 本地对象
        var localDict: [String: T] = [:]
        for obj in existsObjects {
            localDict[obj.objectId] = obj
        }

        // 3️⃣ 遍历传入对象，分类
        var newObjects: [T] = []
        var updatedObjects: [T] = []
        var deletedObjects: [T] = []

        for obj in objects {
            if let local = localDict[obj.objectId] {
                // 本地存在
                if obj.removed {
                    deletedObjects.append(obj)
                } else if obj.modified > local.modified {
                    updatedObjects.append(obj)
                }
            } else {
                // 本地不存在 → 新增
                newObjects.append(obj)
            }
        }

        return DiffSyncableResult(insert: newObjects, updated: updatedObjects, deleted: deletedObjects)
    }

    func pendingUploadEnqueue(sources: [(source: any Syncable, changes: UploadQueue.Changes)], skipEnqueueHandler: Bool = false, handle: Handle? = nil) throws {
        guard !sources.isEmpty else {
            return
        }

        let row = if let handle {
            try handle.getRow(on: UploadQueue.Properties.id.max(), fromTable: UploadQueue.tableName)
        } else {
            try db.getRow(on: UploadQueue.Properties.id.max(), fromTable: UploadQueue.tableName)
        }

        precondition(
            row.count == 1,
            "unexpected result shape when reading max upload queue id",
        )
        var maxId = row[0].int64Value + 1

        let queues = try sources.map {
            let value = try UploadQueue(source: $0.source, changes: $0.changes)
            value.id = maxId
            maxId += 1
            return value
        }

        if let handle {
            try handle.insert(queues, intoTable: UploadQueue.tableName)
        } else {
            try db.insert(queues, intoTable: UploadQueue.tableName)
        }

        if skipEnqueueHandler {
            return
        }

        uploadQueueEnqueueHandler?(queues)
    }

    /// 从上传队列中删除记录
    /// - Parameters:
    ///   - deleting: 待删除集合
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    func pendingUploadDequeue(by deleting: [(queueId: UploadQueue.ID, objectId: String, tableName: String)], handle: Handle? = nil) throws {
        guard !deleting.isEmpty else {
            return
        }

        try runTransaction(handle: handle) {
            for item in deleting {
                try $0.delete(
                    fromTable: UploadQueue.tableName,
                    where: UploadQueue.Properties.id <= item.queueId
                        && UploadQueue.Properties.tableName == item.tableName
                        && UploadQueue.Properties.objectId == item.objectId,
                )
            }
        }
    }

    /// 从上传队列中删除记录
    /// - Parameters:
    ///   - deleting: 待删除集合
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    func pendingUploadDequeueDeleted(by deleting: [(objectId: String, tableName: String)], handle: Handle? = nil) throws {
        guard !deleting.isEmpty else {
            return
        }

        try runTransaction(handle: handle) {
            for item in deleting {
                try $0.delete(
                    fromTable: UploadQueue.tableName,
                    where:
                    UploadQueue.Properties.tableName == item.tableName
                        && UploadQueue.Properties.objectId == item.objectId,
                )

                let recordName = "\(item.objectId)\(UploadQueue.CKRecordIDSeparator)\(item.tableName)"
                try $0.delete(
                    fromTable: SyncMetadata.tableName,
                    where: SyncMetadata.Properties.recordName == recordName,
                )
            }
        }
    }

    /// 批量更新状态
    /// - Parameters:
    ///   - changes: 待更新集合
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    func pendingUploadChangeState(by changes: [(queueId: UploadQueue.ID, state: UploadQueue.State)], handle: Handle? = nil) throws {
        guard !changes.isEmpty else {
            return
        }

        try runTransaction(handle: handle) {
            let grouped = Dictionary(grouping: changes, by: { $0.state })

            for (state, group) in grouped {
                let queueIds = group.map(\.queueId)

                let update = StatementUpdate().update(table: UploadQueue.tableName)
                if case .failed = state {
                    update.set(UploadQueue.Properties.failCount)
                        .to(UploadQueue.Properties.failCount + 1)
                        .set(UploadQueue.Properties.state)
                        .to(UploadQueue.State.pending)
                        .where(UploadQueue.Properties.id.in(queueIds))
                } else {
                    update.set(UploadQueue.Properties.state)
                        .to(state)
                        .where(UploadQueue.Properties.id.in(queueIds))
                }

                try $0.exec(update)
            }
        }
    }

    /// 将状态为failed的记录更为状态为pending
    /// - Parameter handle: 数据库句柄，传入 nil 时使用主句柄
    func pendingUploadRestToPendingState(handle: Handle? = nil) throws {
        let update = StatementUpdate().update(table: UploadQueue.tableName)
        update.set(UploadQueue.Properties.state)
            .to(UploadQueue.State.pending)
            .where(
                UploadQueue.Properties.state == UploadQueue.State.failed
                    && UploadQueue.Properties.failCount < 100,
            )

        if let handle {
            try handle.exec(update)
        } else {
            try db.exec(update)
        }
    }

    /// 查询状态为pending 的集合
    /// - Parameters:
    ///   - tables: 表名集合
    ///   - batchSize: 批次大小
    ///   - queryRealObject: 是否需要查询关联的 realObject
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    /// - Returns: 队列信息， 已按ID进行ascending排序
    func pendingUploadList(tables: [String], batchSize: Int = 0, queryRealObject: Bool = false, handle: Handle? = nil) -> [UploadQueue] {
        guard !tables.isEmpty else {
            return []
        }

        guard let select = if let handle {
            try? handle.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName)
        } else {
            try? db.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName)
        } else {
            return []
        }

        // UploadQueue 是本地的修改历史，理论上只取最新的修改记录为准
        let subSelect = StatementSelect()
            .select(UploadQueue.Properties.id.max())
            .from(UploadQueue.tableName)
            .where(
                UploadQueue.Properties.tableName.in(tables)
                    && UploadQueue.Properties.state == UploadQueue.State.pending
                    && UploadQueue.Properties.failCount < 100,
            )
            .group(by: UploadQueue.Properties.objectId)
            .order(by: UploadQueue.Properties.creation.order(.ascending))

        if batchSize > 0 {
            subSelect.limit(batchSize)
        }

        guard let rows = if let handle {
            try? handle.getRows(from: subSelect)
        } else {
            try? db.getRows(from: subSelect)
        } else {
            return []
        }

        guard !rows.isEmpty else {
            return []
        }

        let ids = rows.map { $0[0].int64Value }

        select.where(
            //            UploadQueue.Properties.id.in(subSelect.asExpression())
            UploadQueue.Properties.id.in(ids),
        )
        .order(by: [
            UploadQueue.Properties.id.order(.ascending),
        ])

        do {
            let objects: [UploadQueue] = try select.allObjects()
            if queryRealObject {
                queryUploadQueueRealObject(objects, handle: handle)
            }
            return objects
        } catch {
            Logger.database.errorFile("query pending upload error: \(error)")
            return []
        }
    }

    /// 查询的指定队列ID集合, state != finish && failCount < 100
    /// - Parameters:
    ///   - queueIds: 队列ID
    ///   - queryRealObject: 是否需要查询关联的 realObject
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    /// - Returns: 队列信息， 已按ID进行ascending排序
    func pendingUploadList(queueIds: [UploadQueue.ID], queryRealObject: Bool = false, handle: Handle? = nil) -> [UploadQueue] {
        guard let select = if let handle {
            try? handle.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName)
        } else {
            try? db.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName)
        } else {
            return []
        }

        select.where(
            UploadQueue.Properties.id.in(queueIds)
                && UploadQueue.Properties.state != UploadQueue.State.finish
                && UploadQueue.Properties.failCount < 100,
        )
        .order(by: [
            UploadQueue.Properties.id.order(.ascending),
        ])

        guard let objects = try? select.allObjects() as? [UploadQueue] else { return [] }

        if queryRealObject {
            queryUploadQueueRealObject(objects, handle: handle)
        }
        return objects
    }

    /// 查询上传队列关联的真实数据对象
    /// - Parameters:
    ///   - objects: 上传队列
    ///   - handle: 数据库句柄，传入 nil 时使用主句柄
    private func queryUploadQueueRealObject(_ objects: [UploadQueue], handle: Handle? = nil) {
        guard !objects.isEmpty else {
            return
        }

        func getObject<T: Syncable & SyncQueryable>(_: T.Type, objectId: String, handle: Handle? = nil) -> T? {
            if let handle {
                try? handle.getObject(fromTable: T.tableName, where: T.SyncQuery.objectId == objectId)
            } else {
                try? db.getObject(fromTable: T.tableName, where: T.SyncQuery.objectId == objectId)
            }
        }

        for object in objects {
            switch object.tableName {
            case CloudModel.tableName:
                object.realObject = getObject(CloudModel.self, objectId: object.objectId, handle: handle)
            case ModelContextServer.tableName:
                object.realObject = getObject(ModelContextServer.self, objectId: object.objectId, handle: handle)
            case Memory.tableName:
                object.realObject = getObject(Memory.self, objectId: object.objectId, handle: handle)
            case Conversation.tableName:
                object.realObject = getObject(Conversation.self, objectId: object.objectId, handle: handle)
            case Message.tableName:
                object.realObject = getObject(Message.self, objectId: object.objectId, handle: handle)
            case Attachment.tableName:
                object.realObject = getObject(Attachment.self, objectId: object.objectId, handle: handle)
            case ChatTemplateRecord.tableName:
                object.realObject = getObject(ChatTemplateRecord.self, objectId: object.objectId, handle: handle)
            default: continue
            }
        }
    }
}

package extension Storage {
    /// 初始化上传队列，通常只在app升级数据迁移或者导入数据库需要执行
    func reinitializeUploadQueue() throws {
        let start = Date.now
        Logger.database.infoFile("[*] reinitializeUploadQueue begin")

        try db.run(transaction: { [weak self] in
            guard let self else { return }

            try $0.delete(fromTable: UploadQueue.tableName)

            let tables: [any (Syncable & SyncQueryable).Type] = [
                CloudModel.self,
                ModelContextServer.self,
                Conversation.self,
                Message.self,
                Attachment.self,
                Memory.self,
                ChatTemplateRecord.self,
            ]

            let row = try $0.getRow(on: UploadQueue.Properties.id.max(), fromTable: UploadQueue.tableName)
            var startId = row[0].int64Value
            for table in tables {
                guard try db.isTableExists(table.tableName) else {
                    Logger.database.infoFile("[*] reinitializeUploadQueue skip missing table \(table.tableName)")
                    continue
                }
                startId = try initializeMigrationUploadQueue(table: table, handle: $0, startId: startId + 1)
            }

        })

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] reinitializeUploadQueue end elapsed \(Int(elapsed))ms")
    }

    private func initializeMigrationUploadQueue<T: Syncable & SyncQueryable>(table _: T.Type, handle: Handle, startId: Int64) throws -> Int64 {
        let batchSize = 500
        var lastObjectId: String?
        var lastCreation: Date?
        var innerStartId = startId
        var lastInsertedRowID = startId

        while true {
            let objects: [T] = if let lastObjectId, let lastCreation {
                try handle.getObjects(
                    fromTable: T.tableName,
                    where:
                    T.SyncQuery.creation >= lastCreation
                        && T.SyncQuery.objectId != lastObjectId,
                    orderBy: [
                        T.SyncQuery.creation.order(.ascending),
                    ],
                    limit: batchSize,
                )
            } else {
                try handle.getObjects(
                    fromTable: T.tableName,
                    orderBy: [
                        T.SyncQuery.creation.order(.ascending),
                    ],
                    limit: batchSize,
                )
            }

            guard !objects.isEmpty else {
                return lastInsertedRowID
            }

            lastObjectId = objects.last?.objectId
            lastCreation = objects.last?.creation
            var queues: [UploadQueue] = []
            for object in objects {
                let queue = try UploadQueue(source: object, changes: object.removed ? .delete : .insert)
                queue.id = innerStartId
                innerStartId += 1
                queues.append(queue)
            }

            try handle.insert(queues, intoTable: UploadQueue.tableName)
            lastInsertedRowID = handle.lastInsertedRowID

            Logger.database.infoFile("[*] firstMigrationUploadQueue \(T.tableName)  -> batch \(queues.count)")
            if objects.count < batchSize {
                break
            }
        }

        return lastInsertedRowID
    }
}

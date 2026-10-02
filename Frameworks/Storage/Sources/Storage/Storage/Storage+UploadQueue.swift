//
//  Storage+UploadQueue.swift
//  Storage
//
//  Created by king on 2025/10/12.
//

import Foundation
import WCDBSwift

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
    ///   - handle: The handle of the enclosing transaction.
    /// - Returns: 三个数组：新增、更新、删除
    func diffSyncable<T: Syncable & SyncQueryable>(
        objects: [T],
        handle: Handle,
    ) throws -> DiffSyncableResult<T> {
        guard !objects.isEmpty else {
            return DiffSyncableResult()
        }

        // 1️⃣ 获取所有 objectId
        let objectIds = objects.map(\.objectId)

        // 2️⃣ 查询本地对应的对象
        let existsObjects: [T] = try handle.getObjects(
            fromTable: T.tableName,
            where: T.SyncQuery.objectId.in(objectIds),
        )

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

    /// Writes the objects that differ from the local rows and queues their changes for upload, oldest first.
    /// - Parameters:
    ///   - objects: The objects to save.
    ///   - restoreInsertModified: Whether a new object's modified time is reset to its creation time.
    ///   - skipSync: Whether the changes stay out of the upload queue.
    func putSyncable<T: Syncable & SyncQueryable & TableEncodable>(
        _ objects: [T],
        restoreInsertModified: Bool = true,
        skipSync: Bool = false,
    ) throws {
        let modified = Date.now

        try runTransaction { [weak self] in
            guard let self else { return }

            let diff = try diffSyncable(objects: objects, handle: $0)
            guard !diff.isEmpty else {
                return
            }

            if restoreInsertModified {
                // 恢复修改时间
                diff.insert.forEach { $0.markModified($0.creation) }
            }

            try $0.insertOrReplace(diff.insertOrReplace(), intoTable: T.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: T.tableName)
                    .set(T.SyncQuery.removed)
                    .to(true)
                    .set(T.SyncQuery.modified)
                    .to(modified)
                    .where(T.SyncQuery.objectId.in(deletedIds))

                try $0.exec(update)
            }

            if skipSync {
                return
            }

            var changes = diff.insert.map { ($0, UploadQueue.Changes.insert) }
                + diff.updated.map { ($0, UploadQueue.Changes.update) }
                + diff.deleted.map { ($0, UploadQueue.Changes.delete) }
            // 按 modified 升序
            changes.sort { $0.0.modified < $1.0.modified }

            try pendingUploadEnqueue(sources: changes, handle: $0)
        }
    }

    func pendingUploadEnqueue(
        sources: [(source: any Syncable, changes: UploadQueue.Changes)],
        skipEnqueueHandler: Bool = false,
        handle: Handle? = nil
    ) throws {
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

        uploadQueueEnqueueHandler?()
    }

    /// 从上传队列中删除记录
    /// - Parameters:
    ///   - deleting: 待删除集合
    ///   - handle: The handle of the enclosing transaction.
    func pendingUploadDequeue(
        by deleting: [(queueId: UploadQueue.ID, objectId: String, tableName: String)],
        handle: Handle
    ) throws {
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
    func pendingUploadDequeueDeleted(
        by deleting: [(objectId: String, tableName: String)],
        handle: Handle? = nil
    ) throws {
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
    func pendingUploadChangeState(by changes: [(queueId: UploadQueue.ID, state: UploadQueue.State)]) throws {
        guard !changes.isEmpty else {
            return
        }

        try runTransaction {
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
    /// - Parameter handle: The handle of the enclosing transaction.
    func pendingUploadRestToPendingState(handle: Handle) throws {
        let update = StatementUpdate().update(table: UploadQueue.tableName)
        update.set(UploadQueue.Properties.state)
            .to(UploadQueue.State.pending)
            .where(
                UploadQueue.Properties.state == UploadQueue.State.failed
                    && UploadQueue.Properties.failCount < 100,
            )

        try handle.exec(update)
    }

    /// 查询状态为pending 的集合
    /// - Parameters:
    ///   - tables: 表名集合
    ///   - batchSize: 批次大小
    /// - Returns: 队列信息， 已按ID进行ascending排序
    func pendingUploadList(tables: [String], batchSize: Int = 0) -> [UploadQueue] {
        guard !tables.isEmpty else {
            return []
        }

        guard let select = try? db.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName) else {
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

        guard let rows = try? db.getRows(from: subSelect) else {
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
    /// - Returns: 队列信息， 已按ID进行ascending排序
    func pendingUploadList(queueIds: [UploadQueue.ID], queryRealObject: Bool = false) -> [UploadQueue] {
        guard let select = try? db.prepareSelect(of: UploadQueue.self, fromTable: UploadQueue.tableName) else {
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
            queryUploadQueueRealObject(objects)
        }
        return objects
    }

    /// 查询上传队列关联的真实数据对象
    /// - Parameter objects: 上传队列
    private func queryUploadQueueRealObject(_ objects: [UploadQueue]) {
        guard !objects.isEmpty else {
            return
        }

        func getObject<T: Syncable & SyncQueryable>(_: T.Type, objectId: String) -> T? {
            try? db.getObject(fromTable: T.tableName, where: T.SyncQuery.objectId == objectId)
        }

        for object in objects {
            switch object.tableName {
            case CloudModel.tableName:
                object.realObject = getObject(CloudModel.self, objectId: object.objectId)
            case ModelContextServer.tableName:
                object.realObject = getObject(ModelContextServer.self, objectId: object.objectId)
            case Memory.tableName:
                object.realObject = getObject(Memory.self, objectId: object.objectId)
            case Conversation.tableName:
                object.realObject = getObject(Conversation.self, objectId: object.objectId)
            case Message.tableName:
                object.realObject = getObject(Message.self, objectId: object.objectId)
            case Attachment.tableName:
                object.realObject = getObject(Attachment.self, objectId: object.objectId)
            case ChatTemplateRecord.tableName:
                object.realObject = getObject(ChatTemplateRecord.self, objectId: object.objectId)
            case ConversationSummary.tableName:
                object.realObject = getObject(ConversationSummary.self, objectId: object.objectId)
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
                ConversationSummary.self,
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

    private func initializeMigrationUploadQueue<T: Syncable & SyncQueryable>(
        table _: T.Type,
        handle: Handle,
        startId: Int64
    ) throws -> Int64 {
        let batchSize = 500
        var lastObjectId: String?
        var lastCreation: Date?
        var innerStartId = startId
        var lastInsertedRowID = startId

        while true {
            // Page by (creation, objectId) so rows sharing a creation time are
            // each read exactly once, however many of them there are.
            let objects: [T] = if let lastObjectId, let lastCreation {
                try handle.getObjects(
                    fromTable: T.tableName,
                    where:
                    T.SyncQuery.creation > lastCreation
                        || (T.SyncQuery.creation == lastCreation && T.SyncQuery.objectId > lastObjectId),
                    orderBy: [
                        T.SyncQuery.creation.order(.ascending),
                        T.SyncQuery.objectId.order(.ascending),
                    ],
                    limit: batchSize,
                )
            } else {
                try handle.getObjects(
                    fromTable: T.tableName,
                    orderBy: [
                        T.SyncQuery.creation.order(.ascending),
                        T.SyncQuery.objectId.order(.ascending),
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

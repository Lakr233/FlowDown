//
//  DBMigration.swift
//  Storage
//
//  Created by KK on 2025/10/9.
//

import Foundation
import Logger
import WCDBSwift

protocol DBMigration {
    var fromVersion: DBVersion { get }
    var toVersion: DBVersion { get }
    var requiresDataMigration: Bool { get }
    func migrate(db: Database) throws
}

extension DBMigration {
    /// 检查迁移是否合法：不允许跨多个版本
    func validate(allowedVersions: [DBVersion]) -> Bool {
        // 1. fromVersion 和 toVersion 都必须在允许的版本范围内
        guard allowedVersions.contains(fromVersion),
              allowedVersions.contains(toVersion)
        else {
            return false
        }

        // 2. 只允许跨单个版本
        if let fromIndex = allowedVersions.firstIndex(of: fromVersion),
           let toIndex = allowedVersions.firstIndex(of: toVersion)
        {
            return (toIndex - fromIndex) == 1
        }
        return false
    }
}

struct MigrationV0ToV1: DBMigration {
    let fromVersion: DBVersion = .Version0
    let toVersion: DBVersion = .Version1
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        try db.create(table: AttachmentV1.tableName, of: AttachmentV1.self)
        try db.create(table: MessageV1.tableName, of: MessageV1.self)
        try db.create(table: ConversationV1.tableName, of: ConversationV1.self)

        try db.create(table: CloudModelV1.tableName, of: CloudModelV1.self)
        try db.create(table: ModelContextServerV1.tableName, of: ModelContextServerV1.self)
        try db.create(table: MemoryV1.tableName, of: MemoryV1.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}

struct MigrationV1ToV2: DBMigration {
    let fromVersion: DBVersion = .Version1
    let toVersion: DBVersion = .Version2
    let deviceId: String
    let requiresDataMigration: Bool

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        if requiresDataMigration {
            try performDataMigration(db: db)
        } else {
            try performSchemaMigration(db: db)
        }

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        if requiresDataMigration {
            // 初始化上传队列
            try initializeUploadQueue(db: db)
        }

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")

        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end")
    }

    private func performSchemaMigration(db: Database) throws {
        try db.create(table: Attachment.tableName, of: Attachment.self)
        try db.create(table: Message.tableName, of: Message.self)
        try db.create(table: Conversation.tableName, of: Conversation.self)

        try db.create(table: CloudModel.tableName, of: CloudModel.self)
        try db.create(table: ModelContextServer.tableName, of: ModelContextServer.self)
        try db.create(table: Memory.tableName, of: Memory.self)

        try db.create(table: SyncMetadata.tableName, of: SyncMetadata.self)
        try db.create(table: UploadQueue.tableName, of: UploadQueue.self)
    }

    private func performDataMigration(db: Database) throws {
        // 重命名旧表
        let oldTableSuffix = "_old"
        let oldTables: [TableNamed.Type] = [
            CloudModelV1.self,
            ModelContextServerV1.self,
            MemoryV1.self,
            ConversationV1.self,
            MessageV1.self,
            AttachmentV1.self,
        ]

        var tableExists: [String: String] = [:]
        for table in oldTables {
            if try db.isTableExists(table.tableName) {
                let oldTableName = "\(table.tableName)\(oldTableSuffix)"
                let alter = StatementAlterTable().alter(table: table.tableName).rename(to: oldTableName)
                try db.exec(alter)
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) rename \(table.tableName) -> \(oldTableName)")
                tableExists[table.tableName] = oldTableName
            }
        }

        // 创建新表
        try performSchemaMigration(db: db)

        try db.run(transaction: { handle in
            if let oldTableName = tableExists[CloudModelV1.tableName] {
                let cloudModelCount = try migrateCloudModels(handle: handle, oldTableName: oldTableName)
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) cloudModels \(cloudModelCount)")
            }

            if let oldTableName = tableExists[ModelContextServerV1.tableName] {
                let modelContextServerCount = try migrateModelContextServers(handle: handle, oldTableName: oldTableName)
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) modelContextServers \(modelContextServerCount)")
            }

            if let oldTableName = tableExists[MemoryV1.tableName] {
                let memoryCount = try migrateMemorys(handle: handle, oldTableName: oldTableName)
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) memorys \(memoryCount)")
            }
        })

        var conversationsMap: [ConversationV1.ID: Conversation] = [:]
        var messagesMap: [MessageV1.ID: Message] = [:]

        // 迁移会话
        if let oldTableName = tableExists[ConversationV1.tableName] {
            try db.run(transaction: { handle in
                conversationsMap = try migrateConversations(handle: handle, oldTableName: oldTableName)
                guard !conversationsMap.isEmpty else {
                    return
                }
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) conversations \(conversationsMap.count)")
            })
        }

        // 迁移消息
        if let oldTableName = tableExists[MessageV1.tableName] {
            try db.run(transaction: { handle in
                messagesMap = try migrateMessages(handle: handle, conversationsMap: conversationsMap, oldTableName: oldTableName)
                guard !messagesMap.isEmpty else {
                    return
                }
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) messages \(messagesMap.count)")
            })
        }

        // 迁移附件
        if let oldTableName = tableExists[AttachmentV1.tableName] {
            try db.run(transaction: { handle in
                let attachments = try migrateAttachments(handle: handle, messagesMap: messagesMap, oldTableName: oldTableName)
                guard !attachments.isEmpty else {
                    return
                }
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) attachments \(attachments.count)")
            })
        }

        // 删除旧表
        for (_, oldTable) in tableExists {
            try db.drop(table: oldTable)
        }
    }

    private func migrateCloudModels(handle: Handle, oldTableName: String) throws -> Int {
        let cloudModels: [CloudModelV1] = try handle.getObjects(fromTable: oldTableName)
        guard !cloudModels.isEmpty else {
            return 0
        }

        var migrateCloudModels: [CloudModel] = []

        for cloudModel in cloudModels {
            let update = CloudModel(deviceId: deviceId)
            update.objectId = cloudModel.id
            update.model_identifier = cloudModel.model_identifier
            update.model_list_endpoint = cloudModel.model_list_endpoint
            update.creation = cloudModel.creation
            update.modified = cloudModel.creation
            update.endpoint = cloudModel.endpoint
            update.token = cloudModel.token
            update.headers = cloudModel.headers
            update.capabilities = cloudModel.capabilities
            update.context = cloudModel.context
            update.comment = cloudModel.comment

            migrateCloudModels.append(update)
        }

        guard !migrateCloudModels.isEmpty else {
            return 0
        }

        try handle.insertOrReplace(migrateCloudModels, intoTable: CloudModel.tableName)
        return migrateCloudModels.count
    }

    private func migrateModelContextServers(handle: Handle, oldTableName: String) throws -> Int {
        let mcss: [ModelContextServerV1] = try handle.getObjects(fromTable: oldTableName)
        guard !mcss.isEmpty else {
            return 0
        }

        var migrateMCSs: [ModelContextServer] = []
        for mcs in mcss {
            let update = ModelContextServer()
            update.objectId = mcs.id
            update.name = mcs.name
            update.comment = mcs.comment
            update.type = mcs.type
            update.endpoint = mcs.endpoint
            update.header = mcs.header
            update.timeout = mcs.timeout
            update.isEnabled = mcs.isEnabled
            update.toolsEnabled = mcs.toolsEnabled
            update.resourcesEnabled = mcs.resourcesEnabled
            update.templateEnabled = mcs.templateEnabled
            update.lastConnected = mcs.lastConnected
            update.connectionStatus = mcs.connectionStatus
            update.capabilities = mcs.capabilities

            migrateMCSs.append(update)
        }

        guard !migrateMCSs.isEmpty else {
            return 0
        }

        try handle.insertOrReplace(migrateMCSs, intoTable: ModelContextServer.tableName)
        return migrateMCSs.count
    }

    private func migrateMemorys(handle: Handle, oldTableName: String) throws -> Int {
        let memorys: [MemoryV1] = try handle.getObjects(fromTable: oldTableName)
        guard !memorys.isEmpty else {
            return 0
        }

        var migrateMemorys: [Memory] = []
        for memory in memorys {
            let update = Memory(deviceId: deviceId, content: memory.content, conversationId: memory.conversationId)
            update.objectId = memory.id
            update.creation = memory.timestamp
            update.modified = memory.timestamp

            migrateMemorys.append(update)
        }

        guard !migrateMemorys.isEmpty else {
            return 0
        }

        try handle.insertOrReplace(migrateMemorys, intoTable: Memory.tableName)
        return migrateMemorys.count
    }

    private func migrateConversations(handle: Handle, oldTableName: String) throws -> [ConversationV1.ID: Conversation] {
        let conversations: [ConversationV1] = try handle.getObjects(fromTable: oldTableName)
        guard !conversations.isEmpty else {
            return [:]
        }

        var migrateConversations: [Conversation] = []
        var migrateConversationsMap: [ConversationV1.ID: Conversation] = [:]
        for conversation in conversations {
            let update = Conversation(deviceId: deviceId)
            update.title = conversation.title
            update.creation = conversation.creation
            update.modified = conversation.creation
            update.icon = conversation.icon
            update.isFavorite = conversation.isFavorite
            update.shouldAutoRename = conversation.shouldAutoRename
            update.modelId = conversation.modelId

            migrateConversations.append(update)
            migrateConversationsMap[conversation.id] = update
        }
        try handle.insertOrReplace(migrateConversations, intoTable: Conversation.tableName)
        return migrateConversationsMap
    }

    private func migrateMessages(handle: Handle, conversationsMap: [ConversationV1.ID: Conversation], oldTableName: String) throws -> [MessageV1.ID: Message] {
        let messages: [MessageV1] = try handle.getObjects(fromTable: oldTableName)

        guard !messages.isEmpty else {
            return [:]
        }

        var migrateMessagess: [Message] = []
        var migrateMessagessMap: [MessageV1.ID: Message] = [:]

        for message in messages {
            guard let conv = conversationsMap[message.conversationId] else { continue }

            let update = Message(deviceId: deviceId)
            update.conversationId = conv.objectId
            update.creation = message.creation
            update.modified = message.creation
            update.role = message.role
            update.thinkingDuration = message.thinkingDuration
            update.reasoningContent = message.reasoningContent
            update.isThinkingFold = message.isThinkingFold
            update.document = message.document
            update.documentNodes = message.documentNodes
            update.webSearchStatus = message.webSearchStatus
            update.toolStatus = message.toolStatus

            migrateMessagess.append(update)
            migrateMessagessMap[message.id] = update
        }

        try handle.insertOrReplace(migrateMessagess, intoTable: Message.tableName)
        return migrateMessagessMap
    }

    private func migrateAttachments(handle: Handle, messagesMap: [MessageV1.ID: Message], oldTableName: String) throws -> [Attachment] {
        let attachments: [AttachmentV1] = try handle.getObjects(fromTable: oldTableName)
        guard !attachments.isEmpty else {
            return []
        }

        let groupedAttachments = Dictionary(grouping: attachments, by: { $0.messageId })
            .mapValues { $0.sorted(by: { $0.id < $1.id }) }

        var migrateAttachment: [Attachment] = []
        for (messageId, sortedAttachments) in groupedAttachments {
            guard let message = messagesMap[messageId] else { continue }

            var createat = message.creation
            for attachment in sortedAttachments {
                let update = Attachment(deviceId: deviceId)
                update.messageId = message.objectId
                update.creation = createat
                update.modified = createat
                update.data = attachment.data
                update.previewImageData = attachment.previewImageData
                update.imageRepresentation = attachment.imageRepresentation
                update.representedDocument = attachment.representedDocument
                update.type = attachment.type
                update.name = attachment.name

                migrateAttachment.append(update)
                createat.addTimeInterval(0.1)
            }
        }

        guard !migrateAttachment.isEmpty else {
            return []
        }

        try handle.insertOrReplace(migrateAttachment, intoTable: Attachment.tableName)

        return migrateAttachment
    }

    /// 初始化上传队列
    private func initializeUploadQueue(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) initializeUploadQueue begin")

        let tables: [any (Syncable & SyncQueryable).Type] = [
            CloudModel.self,
            ModelContextServer.self,
            Conversation.self,
            Message.self,
            Attachment.self,
            Memory.self,
            ChatTemplateRecord.self,
        ]

        let row = try db.getRow(on: UploadQueue.Properties.id.max(), fromTable: UploadQueue.tableName)
        var startId = row[0].int64Value
        for table in tables {
            guard try db.isTableExists(table.tableName) else {
                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) skip upload init for missing table \(table.tableName)")
                continue
            }
            startId = try initializeMigrationUploadQueue(table: table, db: db, startId: startId + 1)
        }

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) initializeUploadQueue end elapsed \(Int(elapsed))ms")
    }

    private func initializeMigrationUploadQueue<T: Syncable & SyncQueryable>(table _: T.Type, db: Database, startId: Int64) throws -> Int64 {
        let batchSize = 500
        var lastObjectId: String?
        var lastCreation: Date?
        var innerStartId = startId
        var lastInsertedRowID = startId

        while true {
            var finish = false
            try db.run(transaction: { handle in
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
                    finish = true
                    return
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

                Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) firstMigrationUploadQueue \(T.tableName)  -> batch \(queues.count)")

                if objects.count < batchSize {
                    finish = true
                }
            })

            if finish {
                break
            }
        }

        return lastInsertedRowID
    }
}

struct MigrationV2ToV3: DBMigration {
    let fromVersion: DBVersion = .Version2
    let toVersion: DBVersion = .Version3
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")
        // 增加了字段
        try db.create(table: Message.tableName, of: Message.self)

        // 调整了索引
        try db.create(table: UploadQueue.tableName, of: UploadQueue.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}

struct MigrationV3ToV4: DBMigration {
    let fromVersion: DBVersion = .Version3
    let toVersion: DBVersion = .Version4
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        // Add bodyFields column to CloudModel table
        try db.create(table: CloudModel.tableName, of: CloudModel.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}

struct MigrationV4ToV5: DBMigration {
    let fromVersion: DBVersion = .Version4
    let toVersion: DBVersion = .Version5
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        try db.create(table: ChatTemplateRecord.tableName, of: ChatTemplateRecord.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}

struct MigrationV5ToV6: DBMigration {
    let fromVersion: DBVersion = .Version5
    let toVersion: DBVersion = .Version6
    let requiresDataMigration: Bool = false

    func migrate(db: Database) throws {
        let start = Date.now
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) begin")

        try db.create(table: ConversationSummary.tableName, of: ConversationSummary.self)

        try db.exec(StatementPragma().pragma(.userVersion).to(toVersion.rawValue))

        let elapsed = Date.now.timeIntervalSince(start) * 1000.0
        Logger.database.infoFile("[*] migrate version \(fromVersion.rawValue) -> \(toVersion.rawValue) end elapsed \(Int(elapsed))ms")
    }
}

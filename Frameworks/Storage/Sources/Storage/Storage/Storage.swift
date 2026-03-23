//
//  Storage.swift
//  Conversation
//
//  Created by 秋星桥 on 1/21/25.
//

import Foundation
import OSLog
import WCDBSwift
import ZIPFoundation

public class Storage {
    private static let DeviceIDKey = "FlowdownStorageDeviceId"
    private static let SyncFirstSetupKey = "FlowdownSyncFirstSetup"

    let db: Database
    let initVersion: DBVersion
    /// 标记为删除的数据在多长时间后，执行物理删除， 默认为： 30天
    static let DeleteAfterDuration: TimeInterval = 60 * 60 * 24 * 30

    public let databaseDir: URL
    public let databaseLocation: URL

    /// SyncEngine 弱引用，用于在数据更新后触发同步
    package weak var syncEngine: SyncEngine?

    /// UploadQueue enqueue 事件回调类型
    package typealias UploadQueueEnqueueHandler = (_ queues: [UploadQueue]) -> Void
    package var uploadQueueEnqueueHandler: UploadQueueEnqueueHandler?

    private let existsDatabaseFile: Bool
    private let migrations: [DBMigration]
    private static var _deviceId: String?

    /// 设备ID，应用卸载重置
    public static var deviceId: String {
        if let _deviceId {
            return _deviceId
        }

        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: DeviceIDKey) {
            _deviceId = id
            return id
        }

        let id = UUID().uuidString
        defaults.set(id, forKey: DeviceIDKey)
        _deviceId = id
        return id
    }

    convenience init(name: String) throws {
        #if DEBUG
            let databaseDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Objects+Debug.db")
        #else
            let databaseDir = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Objects.db")
        #endif

        do {
            try self.init(name: name, databaseDir: databaseDir)
        } catch {
            Logger.database.error("unable to initialize database at \(databaseDir): \(error.localizedDescription)")
            // copy to a backup path
            let backupPath = FileManager.default
                .urls(for: .documentDirectory, in: .userDomainMask)
                .first!
                .appendingPathComponent("Objects+Recovery+\(Date().timeIntervalSince1970).db")
            try? FileManager.default.removeItem(at: backupPath)
            try FileManager.default.moveItem(at: databaseDir, to: backupPath)
            Logger.database.info("moved corrupted database to \(backupPath)")
            // try again
            try self.init(name: name, databaseDir: databaseDir)
        }
    }

    private init(name: String, databaseDir: URL) throws {
        self.databaseDir = databaseDir

        databaseLocation = databaseDir
            .appendingPathComponent("database")
            .appendingPathExtension("db")

        existsDatabaseFile = FileManager.default.fileExists(atPath: databaseLocation.path)

        if existsDatabaseFile {
            initVersion = .Version0
            migrations = [
                MigrationV0ToV1(),
                MigrationV1ToV2(deviceId: Storage.deviceId, requiresDataMigration: true),
                MigrationV2ToV3(),
                MigrationV3ToV4(),
                MigrationV4ToV5(),
                MigrationV5ToV6(),
            ]
        } else {
            initVersion = .Version1
            migrations = [
                MigrationV1ToV2(deviceId: Storage.deviceId, requiresDataMigration: false),
                MigrationV2ToV3(),
                MigrationV3ToV4(),
                MigrationV4ToV5(),
                MigrationV5ToV6(),
            ]
        }

        db = Database(at: databaseLocation.path)

        db.setAutoBackup(enable: true)
        db.setAutoMigration(enable: true)
        db.enableAutoCompression(true)

        // swiftformat:disable:next redundantSelf
        Logger.database.infoFile("[*] database location: \(self.databaseLocation)")

        checkMigration()

        #if DEBUG
            db.traceSQL { _, _, _, sql, _ in
                print("[\(name)-sql]: \(sql)")
            }
        #endif

        try setup(db: db)

        try resetUploadQueueMaxID()

        // 将上传中/上传失败的同步记录重置为Pending
        try db.run(transaction: { [unowned self] in
            try pendingUploadRestToPendingState(handle: $0)
        })
    }

    func setup(db: Database) throws {
        var version = if existsDatabaseFile {
            try currentVersion()
        } else {
            initVersion
        }

        while let migration = migrations.first(where: { $0.fromVersion == version }) {
            try migration.migrate(db: db)
            version = migration.toVersion
        }
    }

    public func reset() {
        db.purge()
        db.close()
        try? FileManager.default.removeItem(at: databaseDir)
        Task.detached {
            try await Task.sleep(for: .seconds(1))
            exit(0)
        }
    }

    func runTransaction(handle: Handle? = nil, _ transaction: @escaping (Handle) throws -> Void) throws {
        if let handle {
            try handle.run(transaction: transaction)
        } else {
            try db.run(transaction: transaction)
        }
    }

    /// 清除本地所有数据
    func clearLocalData() throws {
        try db.run(transaction: {
            try $0.delete(fromTable: CloudModel.tableName)
            try $0.delete(fromTable: Attachment.tableName)
            try $0.delete(fromTable: Message.tableName)
            try $0.delete(fromTable: Conversation.tableName)
            try $0.delete(fromTable: ModelContextServer.tableName)
            try $0.delete(fromTable: Memory.tableName)
            try $0.delete(fromTable: SyncMetadata.tableName)
            try $0.delete(fromTable: UploadQueue.tableName)
            try $0.delete(fromTable: ChatTemplateRecord.tableName)
            try $0.delete(fromTable: ConversationSummary.tableName)

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

    /// 重置上传队列自增ID初始值
    private func resetUploadQueueMaxID() throws {
        let select = StatementSelect().select(UploadQueue.Properties.id.count())
            .from(UploadQueue.tableName)
        let row = try db.getRow(from: select)
        guard let row else { return }

        let count = row[0].int64Value

        guard count == 0 else {
            return
        }

        let nameColumn = WCDBSwift.Column(named: "name")
        let seqColumn = WCDBSwift.Column(named: "seq")
        let updateTableSequence = StatementUpdate()
            .update(table: "sqlite_sequence")
            .set(seqColumn)
            .to(0)
            .where(nameColumn == UploadQueue.tableName)

        try db.exec(updateTableSequence)
    }
}

private extension Storage {
    func checkMigration() {
        for migration in migrations {
            guard migration.validate(allowedVersions: DBVersion.allCases) else {
                fatalError("Invalid migration: \(migration) crosses multiple versions or uses unknown version")
            }
        }
    }

    func currentVersion() throws -> DBVersion {
        let statement = StatementPragma().pragma(.userVersion)
        let result = try db.getValue(from: statement)
        if let result {
            return DBVersion(rawValue: result.intValue) ?? initVersion
        }
        return initVersion
    }

    func setVersion(_ version: DBVersion) throws {
        let statement = StatementPragma().pragma(.userVersion).to(version.rawValue)
        try db.exec(statement)
    }
}

public extension Storage {
    /// 清理无效数据
    func clearDeletedRecords() {
        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }

            let nowDate = Date.now
            let deleteAt = nowDate.addingTimeInterval(-Storage.DeleteAfterDuration)

            do {
                Logger.database.infoFile("clearDeletedRecords begin")
                try db.run(transaction: {
                    try $0.delete(fromTable: Attachment.tableName, where: Attachment.Properties.modified <= deleteAt && Attachment.Properties.removed == true)
                    try $0.delete(fromTable: Message.tableName, where: Message.Properties.modified <= deleteAt && Message.Properties.removed == true)
                    try $0.delete(fromTable: Conversation.tableName, where: Conversation.Properties.modified <= deleteAt && Conversation.Properties.removed == true)
                    try $0.delete(fromTable: CloudModel.tableName, where: CloudModel.Properties.modified <= deleteAt && CloudModel.Properties.removed == true)
                    try $0.delete(fromTable: Memory.tableName, where: Memory.Properties.modified <= deleteAt && Memory.Properties.removed == true)
                    try $0.delete(fromTable: ModelContextServer.tableName, where: ModelContextServer.Properties.modified <= deleteAt && ModelContextServer.Properties.removed == true)
                    try $0.delete(fromTable: ChatTemplateRecord.tableName, where: ChatTemplateRecord.Properties.modified <= deleteAt && ChatTemplateRecord.Properties.removed == true)
                    try $0.delete(fromTable: ConversationSummary.tableName, where: ConversationSummary.Properties.modified <= deleteAt && ConversationSummary.Properties.removed == true)

                    try $0.delete(fromTable: CloudModel.tableName, where: CloudModel.Properties.objectId == "")

                    let syncTables = [
                        Conversation.tableName,
                        Message.tableName,
                        Attachment.tableName,
                        CloudModel.tableName,
                        Memory.tableName,
                        ModelContextServer.tableName,
                        ChatTemplateRecord.tableName,
                    ]

                    // 清理上传队列
                    // 1. 上传成功的
                    // 2. 上传失败次数超过阈值的
                    try $0.delete(
                        fromTable: UploadQueue.tableName,
                        where:
                        UploadQueue.Properties.tableName.in(syncTables)
                            && (UploadQueue.Properties.state == UploadQueue.State.finish
                                || (UploadQueue.Properties.state.in([UploadQueue.State.pending, UploadQueue.State.failed]) && UploadQueue.Properties.failCount >= 100)),
                    )

                })

                let elapsed = Date.now.timeIntervalSince(nowDate) * 1000.0
                Logger.database.infoFile("clearDeletedRecords end elapsed \(Int(elapsed))ms")
            } catch {
                let elapsed = Date.now.timeIntervalSince(nowDate) * 1000.0
                Logger.database.errorFile("clearDeletedRecords elapsed \(Int(elapsed))ms error \(error.localizedDescription)")
            }
        }
    }

    /// 导出数据库
    /// - Returns: 导出结果
    func exportDatabase() -> Result<URL, Error> {
        let exportDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(
            at: exportDir,
            withIntermediateDirectories: true,
        )

        do {
            // 内部会按照数据迁移的流程走,确保相关表一定是存在的
            let exportStorage = try Storage(name: "Export", databaseDir: exportDir)
            var getError: Error?
            try exportStorage.db.run { [self] expdb in
                do {
                    let mods: [CloudModel] = try db.getObjects(fromTable: CloudModel.tableName)
                    try expdb.insert(mods, intoTable: CloudModel.tableName)
                    let cons: [Conversation] = try db.getObjects(fromTable: Conversation.tableName)
                    try expdb.insert(cons, intoTable: Conversation.tableName)
                    let msgs: [Message] = try db.getObjects(fromTable: Message.tableName)
                    try expdb.insert(msgs, intoTable: Message.tableName)
                    let atts: [Attachment] = try db.getObjects(fromTable: Attachment.tableName)
                    try expdb.insert(atts, intoTable: Attachment.tableName)
                    let mems: [Memory] = try db.getObjects(fromTable: Memory.tableName)
                    try expdb.insert(mems, intoTable: Memory.tableName)
                    let templates: [ChatTemplateRecord] = try db.getObjects(fromTable: ChatTemplateRecord.tableName)
                    try expdb.insert(templates, intoTable: ChatTemplateRecord.tableName)
                    let summaries: [ConversationSummary] = try db.getObjects(fromTable: ConversationSummary.tableName)
                    try expdb.insert(summaries, intoTable: ConversationSummary.tableName)
                    return true
                } catch {
                    getError = error
                    return false
                }
            }
            if let error = getError { throw error }

            let sem = DispatchSemaphore(value: 0)
            try exportStorage.db.close {
                sem.signal()
            }
            sem.wait()
        } catch {
            try? FileManager.default.removeItem(at: exportDir)
            return .failure(error)
        }

        return .success(exportDir)
    }

    /// 导入数据库
    /// - Parameters:
    ///   - url: 待导入的数据库文件路径
    ///   - completeHandler: 导入完成回调
    func importDatabase(from url: URL, completeHandler: @escaping (Result<Void, Error>) -> Void) {
        let fm = FileManager.default

        let tempDir = fm
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let unzipTarget = tempDir.appendingPathComponent("imported")

        var originPath = databaseDir.path()
        originPath.removeLast()
        let backupDatabaseDir = URL(filePath: "\(originPath).backup")

        Logger.database.infoFile("Import the database \(unzipTarget)")

        do {
            try fm.createDirectory(at: unzipTarget, withIntermediateDirectories: true)
            try fm.unzipItem(at: url, to: unzipTarget)

            let importedDB = unzipTarget.appendingPathComponent("database.db")
            guard fm.fileExists(atPath: importedDB.path) else {
                throw NSError(domain: "Storage", code: -1, userInfo: [NSLocalizedDescriptionKey: "Missing database.db in archive"])
            }

            Logger.database.infoFile("Import the database and execute the migration.")
            // 内部会按照数据迁移的流程走,确保相关表一定是存在的
            let tempDB = try Storage(name: "Import", databaseDir: unzipTarget)
            // 初始化上传队列
            try tempDB.reinitializeUploadQueue()

            // 关闭数据库
            tempDB.db.close()

            Logger.database.infoFile("Database migration has been successfully imported.")

            Task { @MainActor [self] in
                db.purge()
                db.close()

                defer {
                    Logger.database.infoFile("clear import database tempDir \(tempDir)")
                    try? fm.removeItem(at: tempDir)
                }

                do {
                    if fm.fileExists(atPath: backupDatabaseDir.path()) {
                        try fm.removeItem(at: backupDatabaseDir)
                    }

                    Logger.database.infoFile("Back up the current database")
                    // 备份旧目录
                    try fm.moveItem(at: databaseDir, to: backupDatabaseDir)
                    Logger.database.infoFile("Replace the new database")
                    // 移动新目录
                    try fm.moveItem(at: unzipTarget, to: databaseDir)
                    Logger.database.infoFile("Delete the original database")
                    // 删除备份目录
                    try fm.removeItem(at: backupDatabaseDir)

                    Logger.database.infoFile("Database import successful")

                    completeHandler(.success(()))
                } catch {
                    Logger.database.errorFile("imported database error: \(error)")
                    if fm.fileExists(atPath: backupDatabaseDir.path) {
                        try? fm.moveItem(at: backupDatabaseDir, to: databaseDir)
                    }
                    Task { @MainActor in
                        completeHandler(.failure(error))
                    }
                }
            }

        } catch {
            Logger.database.errorFile("imported database error: \(error)")
            if fm.fileExists(atPath: backupDatabaseDir.path) {
                try? fm.moveItem(at: backupDatabaseDir, to: databaseDir)
            }

            Logger.database.infoFile("clear import database tempDir \(tempDir)")
            try? fm.removeItem(at: tempDir)

            Task { @MainActor in
                completeHandler(.failure(error))
            }
        }
    }
}

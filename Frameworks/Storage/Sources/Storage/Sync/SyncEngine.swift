//
//  SyncEngine.swift
//  Storage
//
//  Created by king on 2025/10/14.
//

import CloudKit
import Foundation
import OrderedCollections

public final class ConversationNotificationInfo: Sendable {
    public let modifications: [Conversation.ID]
    public let deletions: [Conversation.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Conversation.ID], deletions: [Conversation.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class CloudModelNotificationInfo: Sendable {
    public let modifications: [CloudModel.ID]
    public let deletions: [CloudModel.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [CloudModel.ID], deletions: [CloudModel.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class ModelContextServerNotificationInfo: Sendable {
    public let modifications: [ModelContextServer.ID]
    public let deletions: [ModelContextServer.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [ModelContextServer.ID], deletions: [ModelContextServer.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class MemoryNotificationInfo: Sendable {
    public let modifications: [Memory.ID]
    public let deletions: [Memory.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Memory.ID], deletions: [Memory.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class MessageNotificationInfo: Sendable {
    public let modifications: [Conversation.ID: [Message.ID]]
    public let deletions: [Conversation.ID: [Message.ID]]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [Conversation.ID: [Message.ID]], deletions: [Conversation.ID: [Message.ID]]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final class ChatTemplateNotificationInfo: Sendable {
    public let modifications: [ChatTemplateRecord.ID]
    public let deletions: [ChatTemplateRecord.ID]
    public var isEmpty: Bool {
        modifications.isEmpty && deletions.isEmpty
    }

    public init(modifications: [ChatTemplateRecord.ID], deletions: [ChatTemplateRecord.ID]) {
        self.modifications = modifications
        self.deletions = deletions
    }
}

public final actor SyncEngine: Sendable {
    /// 会话列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ConversationChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ConversationChanged")
    /// 消息列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let MessageChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.MessageChanged")
    /// 模型列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let CloudModelChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.CloudModelChanged")
    /// MCP列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ModelContextServerChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ModelContextServerChanged")
    /// 记忆列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let MemoryChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.MemoryChanged")
    /// 模板列表变化通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ChatTemplateChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ChatTemplateChanged")
    /// 本地数据删除通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let LocalDataDeleted: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.LocalDataDeleted")
    /// 云端数据删除通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let ServerDataDeleted: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.ServerDataDeleted")
    /// 同步状态通知, 在 MainActor 中发布。可安全的在UI线程中访问
    public static let SyncStatusChanged: Notification.Name = .init("wiki.qaq.flowdown.SyncEngine.SyncStatusChanged")
    public static let ConversationNotificationKey: String = "Conversation"
    public static let MessageNotificationKey: String = "Message"
    public static let CloudModelNotificationKey: String = "CloudModel"
    public static let ModelContextServerNotificationKey: String = "ModelContextServer"
    public static let MemoryNotificationKey: String = "Memory"
    public static let ChatTemplateNotificationKey: String = "ChatTemplate"

    public nonisolated static let syncEnabledDefaultsKey = "com.flowdown.storage.sync.manually.enabled"

    public nonisolated static var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: syncEnabledDefaultsKey)
    }

    public nonisolated static func setSyncEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: syncEnabledDefaultsKey)
    }

    public nonisolated static func resetCachedState() {
        stateSerializationData = nil
    }

    public enum Mode {
        case live
        case mock
    }

    private static let zoneID: CKRecordZone.ID = .init(zoneName: "FlowDownSync", ownerName: CKCurrentUserDefaultName)
    private static let recordType: CKRecord.RecordType = "SyncObject"

    private static let SyncEngineStateKey: String = "FlowDownSyncEngineState"
    package static let CKRecordSentQueueIdSeparator: String = "##"

    public nonisolated static var isCloudSyncSupported: Bool {
        if #available(iOS 17, macCatalyst 17, *) {
            return true
        }
        return false
    }

    private let createSyncEngine: (@Sendable (SyncEngine) -> AnyObject)?
    private var _syncEngine: AnyObject?

    private let storage: Storage
    package let container: any CloudContainer
    // deprecated: use isAutomaticallySyncEnabled computed property
    private let automaticallySync: Bool

    private nonisolated var isAutomaticallySyncEnabled: Bool { !SyncPreferences.isManualSyncEnabled }

    private var debounceEnqueueTask: Task<Void, Error>?

    private var beginSyncDate: Date = .now
    private var fetchingChangesCount: Int = 0
    private var sendingChangesCount: Int = 0

    private static let LastSyncDateKey = "FlowDownSyncEngineLastSyncDate"

    package static let temporaryAssetStorage = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("wiki.qaq.flowdown.syncengine")
        .appending(component: "Asset")

    /// 最后一次同步时间, 在 MainActor 中更新。可安全的在UI线程中访问
    public private(set) nonisolated static var LastSyncDate: Date? {
        get {
            guard let date = UserDefaults.standard.object(forKey: SyncEngine.LastSyncDateKey) as? Date else {
                return nil
            }
            return date
        }

        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: SyncEngine.LastSyncDateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SyncEngine.LastSyncDateKey)
            }
        }
    }

    /// 当前是否正在同步中, 在 MainActor 中更新。可安全的在UI线程中访问
    public private(set) static var isSynchronizing = false

    private static var stateSerializationData: Data? {
        get {
            UserDefaults.standard.data(forKey: SyncEngine.SyncEngineStateKey)
        }
        set {
            if let newValue {
                UserDefaults.standard.set(newValue, forKey: SyncEngine.SyncEngineStateKey)
            } else {
                UserDefaults.standard.removeObject(forKey: SyncEngine.SyncEngineStateKey)
            }
            UserDefaults.standard.synchronize()
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    private static func decodeStateSerialization() -> CKSyncEngine.State.Serialization? {
        guard let data = stateSerializationData else { return nil }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            Logger.syncEngine.fault("Failed to decode CKSyncEngine state: \(error)")
            return nil
        }
    }

    public init(storage: Storage, containerIdentifier: String, mode: Mode, automaticallySync: Bool = true) {
        let ckContainer = CKContainer(identifier: containerIdentifier)
        let resolvedContainer: any CloudContainer = if SyncEngine.isCloudSyncSupported, case .mock = mode {
            MockCloudContainer.createContainer(identifier: containerIdentifier)
        } else {
            ckContainer
        }

        self.storage = storage
        container = resolvedContainer
        self.automaticallySync = automaticallySync

        if SyncEngine.isCloudSyncSupported {
            if #available(iOS 17, macCatalyst 17, *) {
                if case .mock = mode {
                    let mockContainer = resolvedContainer as! MockCloudContainer
                    let privateDatabase = mockContainer.privateCloudDatabase
                    createSyncEngine = { syncEngine in
                        let mockSyncEngine = MockSyncEngine(database: privateDatabase, parentSyncEngine: syncEngine, state: MockSyncEngineState(), delegate: syncEngine)
                        mockSyncEngine.automaticallySync = syncEngine.automaticallySync
                        return mockSyncEngine
                    }
                } else {
                    createSyncEngine = { syncEngine in
                        let stateSerialization = SyncEngine.decodeStateSerialization()
                        var configuration = CKSyncEngine.Configuration(
                            database: ckContainer.privateCloudDatabase,
                            stateSerialization: stateSerialization,
                            delegate: syncEngine,
                        )
                        configuration.automaticallySync = syncEngine.isAutomaticallySyncEnabled
                        return CKSyncEngine(configuration)
                    }
                }
            } else {
                createSyncEngine = nil
            }
        } else {
            createSyncEngine = nil
        }

        if !FileManager.default.fileExists(atPath: SyncEngine.temporaryAssetStorage.path()) {
            try? FileManager.default.createDirectory(at: SyncEngine.temporaryAssetStorage, withIntermediateDirectories: true)
        }

        storage.uploadQueueEnqueueHandler = { [weak self] _ in
            guard let self else { return }
            Task {
                await self.onUploadQueueEnqueue()
            }
        }

        Task {
            await createCustomZoneIfNeeded()
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    package init(storage: Storage, container: any CloudContainer, automaticallySync: Bool, createSyncEngine: @escaping (SyncEngine) -> any SyncEngineProtocol) {
        self.storage = storage
        self.container = container
        self.automaticallySync = automaticallySync
        self.createSyncEngine = { syncEngine in
            createSyncEngine(syncEngine)
        }

        if !FileManager.default.fileExists(atPath: SyncEngine.temporaryAssetStorage.path()) {
            try? FileManager.default.createDirectory(at: SyncEngine.temporaryAssetStorage, withIntermediateDirectories: true)
        }

        storage.uploadQueueEnqueueHandler = { [weak self] _ in
            guard SyncEngine.isSyncEnabled else { return }
            guard let self else { return }

            Task {
                await self.onUploadQueueEnqueue()
            }
        }

        Task {
            await createCustomZoneIfNeeded()
        }
    }
}

public extension SyncEngine {
    /// 停止同步
    func stopSyncIfNeeded() async throws {
        if _syncEngine == nil {
            return
        }

        if #available(iOS 17, macCatalyst 17, *),
           let syncEngine = _syncEngine as? (any SyncEngineProtocol)
        {
            await syncEngine.cancelOperations()
        }
        _syncEngine = nil
        sendingChangesCount = 0
        fetchingChangesCount = 0

        await MainActor.run {
            SyncEngine.LastSyncDate = .now
            SyncEngine.isSynchronizing = false
            NotificationCenter.default.post(
                name: SyncEngine.SyncStatusChanged,
                object: nil,
                userInfo: [
                    "isSynchronizing": false,
                ],
            )
        }

        Logger.syncEngine.infoFile("StopSyncIfNeeded")
    }

    /// 恢复同步
    func resumeSyncIfNeeded() async throws {
        Logger.syncEngine.infoFile("ResumeSyncIfNeeded")
        try await fetchChanges()
    }

    /// 拉取变化 !不要在代理回调里面调用!
    func fetchChanges() async throws {
        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip fetchChanges because cloud sync is not supported")
            return
        }

        guard SyncEngine.isSyncEnabled else {
            Logger.syncEngine.infoFile("Skip fetchChanges because sync is disabled")
            return
        }

        // 这里不检查账户，由后面的 handleAccountChange 事件统一处理账户变化
//        let accountStatus = try await container.accountStatus()
//        guard accountStatus == .available else { return }

        if #available(iOS 17, macCatalyst 17, *) {
            var needDelay = false
            let syncEngine = try await syncEngineOrThrow(initializingIfNeeded: true, needDelay: &needDelay)
            Logger.syncEngine.infoFile("FetchChanges")
            if needDelay {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try await syncEngine.performingFetchChanges()
            return
        }

        throw NSError(domain: "Storage.SyncEngine", code: 3)
    }

    /// 发送变化 !不要在代理回调里面调用!
    func sendChanges() async throws {
        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip sendChanges because cloud sync is not supported")
            return
        }

        guard SyncEngine.isSyncEnabled else {
            Logger.syncEngine.infoFile("Skip sendChanges because sync is disabled")
            return
        }
        if #available(iOS 17, macCatalyst 17, *) {
            var needDelay = false
            let syncEngine = try await syncEngineOrThrow(initializingIfNeeded: true, needDelay: &needDelay)
            Logger.syncEngine.infoFile("SendChanges")
            if needDelay {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
            try await syncEngine.performingSendChanges()
            return
        }

        throw NSError(domain: "Storage.SyncEngine", code: 3)
    }

    /// 删除本地数据
    func deleteLocalData() async throws {
        Logger.syncEngine.infoFile("Deleting local data")

        try storage.clearLocalData()

        // 如果我们要删除所有内容，也需要清除我们的同步引擎状态。
        // 为了做到这一点，也需要重新初始化同步引擎。
        SyncEngine.stateSerializationData = nil
        if SyncEngine.isCloudSyncSupported, #available(iOS 17, macCatalyst 17, *) {
            initializeSyncEngine()
        }

        await MainActor.run {
            NotificationCenter.default.post(
                name: SyncEngine.LocalDataDeleted,
                object: nil,
            )
        }
    }

    /// 删除云端数据
    func deleteServerData() async throws {
        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip deleteServerData because cloud sync is not supported")
            return
        }

        if #available(iOS 17, macCatalyst 17, *) {
            var needDelay = false
            let syncEngine = try await syncEngineOrThrow(initializingIfNeeded: true, needDelay: &needDelay)

            Logger.syncEngine.infoFile("Deleting server data")
            if needDelay {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }

            syncEngine.state.add(pendingDatabaseChanges: [.deleteZone(SyncEngine.zoneID)])
            try await syncEngine.performingSendChanges()
            return
        }

        throw NSError(domain: "Storage.SyncEngine", code: 3)
    }

    /// 强制重新从云端获取
    func reloadDataForcefully() async throws {
        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip reloadDataForcefully because cloud sync is not supported")
            return
        }

        Logger.syncEngine.infoFile("Reload data force fully")

        if #available(iOS 17, macCatalyst 17, *),
           let syncEngine = _syncEngine as? (any SyncEngineProtocol)
        {
            await syncEngine.cancelOperations()
        }

        SyncEngine.stateSerializationData = nil

        if #available(iOS 17, macCatalyst 17, *) {
            var needDelay = false
            let syncEngine = try await syncEngineOrThrow(initializingIfNeeded: true, needDelay: &needDelay)

            // 确保首次开启或重置后自定义 Zone 已创建，避免后续发送报 zoneNotFound
            await createCustomZoneIfNeeded(true)
            try await Task.sleep(nanoseconds: 1_000_000_000)
            try await syncEngine.performingFetchChanges()
            return
        }

        throw NSError(domain: "Storage.SyncEngine", code: 3)
    }
}

private extension SyncEngine {
    @available(iOS 17, macCatalyst 17, *)
    func syncEngineOrThrow(initializingIfNeeded: Bool, needDelay: inout Bool) async throws -> any SyncEngineProtocol {
        guard SyncEngine.isCloudSyncSupported else {
            throw NSError(domain: "Storage.SyncEngine", code: 1)
        }

        if _syncEngine == nil, initializingIfNeeded {
            initializeSyncEngine()
            needDelay = true
        }

        guard let syncEngine = _syncEngine as? (any SyncEngineProtocol) else {
            throw NSError(domain: "Storage.SyncEngine", code: 2)
        }

        return syncEngine
    }

    @available(iOS 17, macCatalyst 17, *)
    func initializeSyncEngine() {
        guard SyncEngine.isCloudSyncSupported else {
            _syncEngine = nil
            return
        }

        guard let createSyncEngine else {
            _syncEngine = nil
            return
        }

        let syncEngine = createSyncEngine(self)
        _syncEngine = syncEngine
        Logger.syncEngine.infoFile("Initialized sync engine: \(syncEngine)")
    }

    /// 创建CKRecordZone
    /// - Parameter immediateSendChanges: 是否立即发送变化，仅在 automaticallySync = false 有效
    func createCustomZoneIfNeeded(_ immediateSendChanges: Bool = false) async {
        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip createCustomZoneIfNeeded because cloud sync is not supported")
            return
        }

        guard SyncEngine.isSyncEnabled else {
            Logger.syncEngine.infoFile("Skip createCustomZoneIfNeeded because sync is disabled")
            return
        }

        do {
            let existingZones = try await container.privateCloudDatabase.allRecordZones()
            if existingZones.contains(where: { $0.zoneID == SyncEngine.zoneID }) {
                Logger.syncEngine.infoFile("Zone already exists")
            } else {
                Logger.syncEngine.infoFile("Creating custom zone \(SyncEngine.zoneID)")
                let zone = CKRecordZone(zoneID: SyncEngine.zoneID)

                if #available(iOS 17, macCatalyst 17, *) {
                    var needDelay = false
                    if let syncEngine = try? await syncEngineOrThrow(initializingIfNeeded: false, needDelay: &needDelay) {
                        syncEngine.state.add(pendingDatabaseChanges: [.saveZone(zone)])
                        if !isAutomaticallySyncEnabled, immediateSendChanges {
                            try await syncEngine.performingSendChanges()
                        }
                    }
                }
            }
        } catch {
            Logger.syncEngine.fault("Failed to createCustomZoneIfNeeded: \(error)")
        }
    }

    func onUploadQueueEnqueue() async {
        debounceEnqueueTask?.cancel()

        debounceEnqueueTask = Task { [weak self] in
            guard let self else { return }

            /// 调整为3s， 减少推理时频繁更新
            try await Task.sleep(nanoseconds: 3_000_000_000)

            try Task.checkCancellation()

            if #available(iOS 17, macCatalyst 17, *) {
                try await scheduleUploadIfNeeded()
            }
        }
    }

    /// 调度上传队列
    /// - Parameter immediateSendChanges: 是否立即发送变化，仅在 automaticallySync = false 有效
    @available(iOS 17, macCatalyst 17, *)
    func scheduleUploadIfNeeded(_ immediateSendChanges: Bool = false) async throws {
        try Task.checkCancellation()

        guard SyncEngine.isCloudSyncSupported else {
            Logger.syncEngine.infoFile("Skip scheduleUploadIfNeeded because cloud sync is not supported")
            return
        }

        guard SyncEngine.isSyncEnabled else {
            Logger.syncEngine.infoFile("Skip scheduleUploadIfNeeded because sync is disabled")
            return
        }

        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            Logger.syncEngine.infoFile("Skip scheduleUploadIfNeeded because accountStatus=\(accountStatus.rawValue)")
            return
        }

        // 查出UploadQueue 队列中的数据 构建 CKSyncEngine Changes
        // 每次最多发送100条
        let tables = SyncPreferences.enabledTables()
        guard !tables.isEmpty else {
            return
        }

        let batchSize = 100
        let objects = storage.pendingUploadList(tables: tables, batchSize: batchSize)

        Logger.syncEngine.infoFile("ScheduleUpload \(objects.count)")
        guard !objects.isEmpty else {
            return
        }

        if _syncEngine == nil {
            return
        }

        var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] = []

        let deviceId = Storage.deviceId
        /// CKSyncEngine 需要的是数据对应的ID。
        /// UploadQueue 中是记录了所有的历史操作
        /// 所以这里对于recordName 额外处理
        for object in objects {
            if case .delete = object.changes {
                pendingRecordZoneChanges.append(.deleteRecord(CKRecord.ID(recordName: object.ckRecordID, zoneID: SyncEngine.zoneID)))
            } else {
                let sentQueueId = SyncEngine.makeCKRecordSentQueueId(queueId: object.id, objectId: object.objectId, deviceId: deviceId)
                pendingRecordZoneChanges.append(.saveRecord(CKRecord.ID(recordName: sentQueueId, zoneID: SyncEngine.zoneID)))
            }
        }

        try Task.checkCancellation()

        if _syncEngine == nil {
            return
        }

        if !pendingRecordZoneChanges.isEmpty {
            var needDelay = false
            if let syncEngine = try? await syncEngineOrThrow(initializingIfNeeded: false, needDelay: &needDelay) {
                syncEngine.state.add(pendingRecordZoneChanges: pendingRecordZoneChanges)

                if !isAutomaticallySyncEnabled, immediateSendChanges {
                    try await syncEngine.performingSendChanges()
                }
            }
        }
    }

    func enqueueSendingChanges() async {
        sendingChangesCount += 1
        if sendingChangesCount == 1, fetchingChangesCount == 0 {
            beginSyncDate = .now
            Logger.syncEngine.infoFile("Begin synchronization")
            await MainActor.run {
                SyncEngine.isSynchronizing = true
                NotificationCenter.default.post(
                    name: SyncEngine.SyncStatusChanged,
                    object: nil,
                    userInfo: [
                        "isSynchronizing": true,
                    ],
                )
            }
        }
    }

    func dequeueSendingChanges() async {
        sendingChangesCount = max(sendingChangesCount - 1, 0)

        if sendingChangesCount == 0, fetchingChangesCount == 0 {
            let nowDate = Date.now
            let elapsed = nowDate.timeIntervalSince(beginSyncDate) * 1000.0
            // swiftformat:disable:next redundantSelf
            Logger.syncEngine.infoFile("Finish synchronization beging \(self.beginSyncDate) elapsed \(Int(elapsed))ms")
            await MainActor.run {
                SyncEngine.LastSyncDate = nowDate
                SyncEngine.isSynchronizing = false
                NotificationCenter.default.post(
                    name: SyncEngine.SyncStatusChanged,
                    object: nil,
                    userInfo: [
                        "isSynchronizing": false,
                    ],
                )
            }
        }
    }

    func enqueueFetchingChanges() async {
        fetchingChangesCount += 1
        if fetchingChangesCount == 1, sendingChangesCount == 0 {
            beginSyncDate = .now
            Logger.syncEngine.infoFile("Begin synchronization")
            await MainActor.run {
                SyncEngine.isSynchronizing = true
                NotificationCenter.default.post(
                    name: SyncEngine.SyncStatusChanged,
                    object: nil,
                    userInfo: [
                        "isSynchronizing": true,
                    ],
                )
            }
        }
    }

    func dequeueFetchingChanges() async {
        fetchingChangesCount = max(fetchingChangesCount - 1, 0)

        if fetchingChangesCount == 0, sendingChangesCount == 0 {
            let nowDate = Date.now
            let elapsed = nowDate.timeIntervalSince(beginSyncDate) * 1000.0
            // swiftformat:disable:next redundantSelf
            Logger.syncEngine.infoFile("Finish synchronization beging \(self.beginSyncDate) elapsed \(Int(elapsed))ms")
            await MainActor.run {
                SyncEngine.LastSyncDate = nowDate
                SyncEngine.isSynchronizing = false
                NotificationCenter.default.post(
                    name: SyncEngine.SyncStatusChanged,
                    object: nil,
                    userInfo: [
                        "isSynchronizing": false,
                    ],
                )
            }
        }
    }

    // MARK: - SyncEngine Events

    /// 注意: ⚠️ 代理回调中，不能调用 syncEngine 的 cancelOperations performingSendChanges performingFetchChanges

    @available(iOS 17, macCatalyst 17, *)
    func handleAccountChange(
        changeType: CKSyncEngine.Event.AccountChange.ChangeType,
        syncEngine _: any SyncEngineProtocol,
    ) async {
        let shouldDeleteLocalData: Bool
        let shouldReUploadLocalData: Bool

        switch changeType {
        case .signIn:
            Logger.syncEngine.infoFile("HandleAccountChange signIn")
            shouldDeleteLocalData = false
            shouldReUploadLocalData = true

        case .switchAccounts:
            Logger.syncEngine.infoFile("HandleAccountChange switchAccounts")
            shouldDeleteLocalData = true
            shouldReUploadLocalData = false

        case .signOut:
            Logger.syncEngine.infoFile("HandleAccountChange signOut")
            shouldDeleteLocalData = true
            shouldReUploadLocalData = false

        @unknown default:
            Logger.syncEngine.infoFile("Unknown account change")
            shouldDeleteLocalData = false
            shouldReUploadLocalData = false
        }

        if shouldDeleteLocalData {
            try? await deleteLocalData()
        }

        if shouldReUploadLocalData {
            await createCustomZoneIfNeeded()
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    func handleStateUpdate(
        stateSerialization: CKSyncEngine.State.Serialization,
        syncEngine _: any SyncEngineProtocol,
    ) async {
        SyncEngine.stateSerializationData = try? JSONEncoder().encode(stateSerialization)
    }

    @available(iOS 17, macCatalyst 17, *)
    func handleFetchedDatabaseChanges(
        modifications: [CKRecordZone.ID],
        deletions: [(zoneID: CKRecordZone.ID, reason: CKDatabase.DatabaseChange.Deletion.Reason)],
        syncEngine _: any SyncEngineProtocol,
    ) async {
        Logger.syncEngine.infoFile("Received DatabaseChanges modifications: \(modifications.count) deletions: \(deletions.count)")

        var resetLocalData = false
        for deletion in deletions {
            switch deletion.zoneID.zoneName {
            case SyncEngine.zoneID.zoneName:
                resetLocalData = true
                Logger.syncEngine.infoFile("Received deletion zone \(deletion.zoneID)")
            default:
                Logger.syncEngine.infoFile("Received deletion for unknown zone: \(deletion.zoneID)")
            }
        }

        if resetLocalData {
            /// 收到其他设备发出的删除操作，当前设备应该同步清除本地所有数据
//            try? await deleteLocalData()
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    func handleFetchedRecordZoneChanges(
        modifications: [CKRecord] = [],
        deletions: [(recordID: CKRecord.ID, recordType: CKRecord.RecordType)] = [],
        syncEngine _: any SyncEngineProtocol,
    ) async {
        Logger.syncEngine.infoFile("Received RecordZoneChanges modifications: \(modifications.count) deletions: \(deletions.count)")

        // Filter by user group preferences
        let filteredModifications = modifications.filter { record in
            guard let (_, tableName) = UploadQueue.parseCKRecordID(record.recordID.recordName) else { return true }
            return SyncPreferences.isTableSyncEnabled(tableName: tableName)
        }

        do {
            try storage.handleRemoteUpsert(modifications: filteredModifications)
        } catch {
            Logger.syncEngine.errorFile("HandleRemoteUpsert error \(error)")
        }

        let filteredDeletions = deletions.filter { deletion in
            guard let (_, tableName) = UploadQueue.parseCKRecordID(deletion.recordID.recordName) else { return true }
            return SyncPreferences.isTableSyncEnabled(tableName: tableName)
        }

        do {
            try storage.handleRemoteDeleted(deletions: filteredDeletions)
        } catch {
            Logger.syncEngine.errorFile("HandleRemoteDeleted error \(error)")
        }

        // 收集变化
        var modificationConversations: [Conversation.ID] = []
        var modificationMessages: [Message.ID] = []
        var modificationCloudModels: [CloudModel.ID] = []
        var modificationMCPS: [ModelContextServer.ID] = []
        var modificationMemorys: [Memory.ID] = []
        var modificationTemplates: [ChatTemplateRecord.ID] = []

        for modification in filteredModifications {
            let recordID = modification.recordID
            guard let (objectId, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }
            if tableName == Conversation.tableName {
                modificationConversations.append(objectId)
            } else if tableName == Message.tableName {
                modificationMessages.append(objectId)
            } else if tableName == CloudModel.tableName {
                modificationCloudModels.append(objectId)
            } else if tableName == ModelContextServer.tableName {
                modificationMCPS.append(objectId)
            } else if tableName == Memory.tableName {
                modificationMemorys.append(objectId)
            } else if tableName == ChatTemplateRecord.tableName {
                modificationTemplates.append(objectId)
            }
        }

        var deletedConversations: [Conversation.ID] = []
        var deletedMessages: [Message.ID] = []
        var deletedCloudModels: [CloudModel.ID] = []
        var deletedMCPS: [ModelContextServer.ID] = []
        var deletedMemorys: [Memory.ID] = []
        var deletedTemplates: [ChatTemplateRecord.ID] = []
        for deletion in filteredDeletions {
            let recordID = deletion.recordID
            guard let (objectId, tableName) = UploadQueue.parseCKRecordID(recordID.recordName) else { continue }
            if tableName == Conversation.tableName {
                deletedConversations.append(objectId)
            } else if tableName == Message.tableName {
                deletedMessages.append(objectId)
            } else if tableName == CloudModel.tableName {
                deletedCloudModels.append(objectId)
            } else if tableName == ModelContextServer.tableName {
                deletedMCPS.append(objectId)
            } else if tableName == Memory.tableName {
                deletedMemorys.append(objectId)
            } else if tableName == ChatTemplateRecord.tableName {
                deletedTemplates.append(objectId)
            }
        }

        var modificationMessageMap: [Conversation.ID: [Message.ID]] = [:]
        var deletionMessageMap: [Conversation.ID: [Message.ID]] = [:]
        if !modificationMessages.isEmpty {
            modificationMessageMap = storage.conversationIds(by: modificationMessages)
        }

        if !deletedMessages.isEmpty {
            deletionMessageMap = storage.conversationIds(by: deletedMessages)
        }

        let conversationNotificationInfo = ConversationNotificationInfo(modifications: modificationConversations, deletions: deletedConversations)
        let messageNotificationInfo = MessageNotificationInfo(modifications: modificationMessageMap, deletions: deletionMessageMap)
        let cloudModelNotificationInfo = CloudModelNotificationInfo(modifications: modificationCloudModels, deletions: deletedCloudModels)
        let MCPNotificationInfo = ModelContextServerNotificationInfo(modifications: modificationMCPS, deletions: deletedMCPS)
        let memoryNotificationInfo = MemoryNotificationInfo(modifications: modificationMemorys, deletions: deletedMemorys)
        let templateNotificationInfo = ChatTemplateNotificationInfo(modifications: modificationTemplates, deletions: deletedTemplates)

        await MainActor.run {
            if !conversationNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.ConversationChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.ConversationNotificationKey: conversationNotificationInfo,
                    ],
                )
            }

            if !messageNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.MessageChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.MessageNotificationKey: messageNotificationInfo,
                    ],
                )
            }

            if !cloudModelNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.CloudModelChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.CloudModelNotificationKey: cloudModelNotificationInfo,
                    ],
                )
            }

            if !MCPNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.ModelContextServerChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.ModelContextServerNotificationKey: MCPNotificationInfo,
                    ],
                )
            }

            if !memoryNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.MemoryChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.MemoryNotificationKey: memoryNotificationInfo,
                    ],
                )
            }

            if !templateNotificationInfo.isEmpty {
                NotificationCenter.default.post(
                    name: SyncEngine.ChatTemplateChanged,
                    object: nil,
                    userInfo: [
                        SyncEngine.ChatTemplateNotificationKey: templateNotificationInfo,
                    ],
                )
            }
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    func handleSentDatabaseChanges(
        savedRecordZones: [CKRecordZone] = [],
        failedRecordZoneSaves: [(zone: CKRecordZone, error: CKError)] = [],
        deletedRecordZoneIDs: [CKRecordZone.ID] = [],
        failedRecordZoneDeletes: [CKRecordZone.ID: CKError] = [:],
        syncEngine _: any SyncEngineProtocol,
    ) async {
        for savedRecordZone in savedRecordZones {
            Logger.syncEngine.infoFile("SavedRecordZone: \(savedRecordZone.zoneID)")
        }

        for (zoneId, error) in failedRecordZoneSaves {
            Logger.syncEngine.errorFile("FailedRecordZoneSave: \(zoneId) \(error)")
        }

        for deletedRecordZoneId in deletedRecordZoneIDs {
            Logger.syncEngine.infoFile("DeletedRecordZone: \(deletedRecordZoneId)")
            if deletedRecordZoneId == SyncEngine.zoneID {
                // 云端删除zone成功后，需要将本地保存的云端记录元数据删除
//                try? storage.syncMetadataRemoveAll()

                await MainActor.run {
                    NotificationCenter.default.post(
                        name: SyncEngine.ServerDataDeleted,
                        object: nil,
                        userInfo: [
                            "success": true,
                        ],
                    )
                }
            }
        }

        for (zoneId, error) in failedRecordZoneDeletes {
            Logger.syncEngine.errorFile("failedRecordZoneDelete: \(zoneId) \(error)")
            if zoneId == SyncEngine.zoneID {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: SyncEngine.ServerDataDeleted,
                        object: nil,
                        userInfo: [
                            "success": false,
                            "error": error,
                        ],
                    )
                }
            }
        }
    }

    @available(iOS 17, macCatalyst 17, *)
    func handleSentRecordZoneChanges(
        savedRecords: [CKRecord] = [],
        failedRecordSaves: [(record: CKRecord, error: CKError)] = [],
        deletedRecordIDs: [CKRecord.ID] = [],
        failedRecordDeletes: [CKRecord.ID: CKError] = [:],
        syncEngine: any SyncEngineProtocol,
    ) async {
        var newPendingDatabaseChanges = [CKSyncEngine.PendingDatabaseChange]()
        var removePendingRecordZoneChanges = [CKSyncEngine.PendingRecordZoneChange]()
        // 发送成功的，需要更新本地UploadQueue 状态
        if !savedRecords.isEmpty {
            var savedLocalQueueIds: [(queueId: UploadQueue.ID, objectId: String, tableName: String)] = []
            var metadatas: [SyncMetadata] = []
            for savedRecord in savedRecords {
                guard let (_, tableName) = UploadQueue.parseCKRecordID(savedRecord.recordID.recordName) else { continue }
                guard let value = savedRecord.sentQueueId, let (localQueueId, objectId, _) = SyncEngine.parseCKRecordSentQueueId(value) else { continue }
                /// 这里回调成功都是本地发送的结果，不存在远端其他设备的结果，所以无需判断设备ID。
                savedLocalQueueIds.append((localQueueId, objectId, tableName))
                metadatas.append(SyncMetadata(record: savedRecord))
                // 清理临时文件
                savedRecord.clearTemporaryAssets(prefix: SyncEngine.temporaryAssetStorage)
            }

            Logger.syncEngine.infoFile("Sent save success record zone: \(savedLocalQueueIds)")
            try? storage.runTransaction {
                try self.storage.syncMetadataUpdate(metadatas, handle: $0)
                try self.storage.pendingUploadDequeue(by: savedLocalQueueIds, handle: $0)
            }
        }

        var pendingUploadChangeStates: [(queueId: UploadQueue.ID, state: UploadQueue.State)] = []

        //  发送失败
        for failedRecordSave in failedRecordSaves {
            let failedRecord = failedRecordSave.record
            // 清理临时文件
            failedRecord.clearTemporaryAssets(prefix: SyncEngine.temporaryAssetStorage)

            switch failedRecordSave.error.code {
            case .serverRecordChanged:
                removePendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))

                guard let sentQueueId = failedRecord.sentQueueId, let (localQueueId, _, _) = SyncEngine.parseCKRecordSentQueueId(sentQueueId) else { continue }

                guard let serverRecord = failedRecordSave.error.serverRecord else {
                    Logger.syncEngine.errorFile("No server record for conflict \(failedRecordSave.error)")

                    pendingUploadChangeStates.append((localQueueId, .failed))
                    continue
                }

                // 处理冲突
                try? storage.syncMetadataUpdate([SyncMetadata(record: serverRecord)])
                pendingUploadChangeStates.append((localQueueId, .pending))

            case .zoneNotFound:
                Logger.syncEngine.errorFile("zoneNotFound error saving \(failedRecord.recordID): \(failedRecordSave.error)")
                let zone = CKRecordZone(zoneID: failedRecord.recordID.zoneID)
                if failedRecordSave.error.userInfo[CKErrorUserDidResetEncryptedDataKey] != nil {
                    // CloudKit is unable to decrypt previously encrypted data. This occurs when a user
                    // resets their iCloud Keychain and thus deletes the key material previously used
                    // to encrypt and decrypt their encrypted fields stored via CloudKit.
                    // In this case, it is recommended to delete the associated zone and re-upload any
                    // locally cached data, which will be encrypted with the new key.

                    newPendingDatabaseChanges.append(.deleteZone(zone.zoneID))
                } else {
                    newPendingDatabaseChanges.append(.saveZone(zone))
                }

                guard let sentQueueId = failedRecord.sentQueueId, let (localQueueId, _, _) = SyncEngine.parseCKRecordSentQueueId(sentQueueId) else { continue }
                pendingUploadChangeStates.append((localQueueId, .pending))

            case .unknownItem:
                Logger.syncEngine.errorFile("unknownItem error saving \(failedRecord.recordID): \(failedRecordSave.error)")
                // 删除本地记录的云端记录
                let recordID = failedRecord.recordID
                let zoneID = recordID.zoneID
                try? storage.syncMetadataRemove(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName, recordName: recordID.recordName)

                removePendingRecordZoneChanges.append(.saveRecord(recordID))

                guard let sentQueueId = failedRecord.sentQueueId, let (localQueueId, _, _) = SyncEngine.parseCKRecordSentQueueId(sentQueueId) else { continue }
                pendingUploadChangeStates.append((localQueueId, .failed))

            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                // 可重试错误也直接从state中删除，由后续的调度策略再次自动加入
                removePendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                Logger.syncEngine.errorFile("Retryable error saving \(failedRecord.recordID): \(failedRecordSave.error)")

                guard let sentQueueId = failedRecord.sentQueueId, let (localQueueId, _, _) = SyncEngine.parseCKRecordSentQueueId(sentQueueId) else { continue }
                pendingUploadChangeStates.append((localQueueId, .pending))

            default:
                removePendingRecordZoneChanges.append(.saveRecord(failedRecord.recordID))
                Logger.syncEngine.fault("Unknown error saving record \(failedRecord.recordID): \(failedRecordSave.error)")

                guard let sentQueueId = failedRecord.sentQueueId, let (localQueueId, _, _) = SyncEngine.parseCKRecordSentQueueId(sentQueueId) else { continue }
                pendingUploadChangeStates.append((localQueueId, .failed))
            }
        }

        try? storage.pendingUploadChangeState(by: pendingUploadChangeStates)

        var finalDeletedRecordIDs = deletedRecordIDs

        for (recordID, error) in failedRecordDeletes {
            switch error.code {
            case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated, .operationCancelled:
                // There are several errors that the sync engine will automatically retry, let's just log and move on.
                Logger.database.errorFile("Retryable error deleting \(recordID): \(error)")

            default:
                finalDeletedRecordIDs.append(recordID)
                Logger.syncEngine.fault("Unknown error deleting record \(recordID): \(error)")
            }
        }

        if !finalDeletedRecordIDs.isEmpty {
            let deletedQueueObjectIds = deletedRecordIDs.compactMap { UploadQueue.parseCKRecordID($0.recordName) }
            Logger.syncEngine.debugFile("Sent deleted success record zone: \(deletedQueueObjectIds)")
            try? storage.pendingUploadDequeueDeleted(by: deletedQueueObjectIds)
        }

        if SyncEngine.isCloudSyncSupported {
            syncEngine.state.remove(pendingRecordZoneChanges: removePendingRecordZoneChanges)
            syncEngine.state.add(pendingDatabaseChanges: newPendingDatabaseChanges)
        }
    }
}

private extension SyncEngine {
    /// 创建发送队列ID
    /// - Parameters:
    ///   - queueId: 本地队列ID
    ///   - objectId: 源数据ID
    ///   - deviceId: 设备ID，应该始终使用 `Storage.deviceId`
    /// - Returns: 发送队列ID
    static func makeCKRecordSentQueueId(queueId: UploadQueue.ID, objectId: String, deviceId: String) -> String {
        "\(queueId)\(SyncEngine.CKRecordSentQueueIdSeparator)\(objectId)\(SyncEngine.CKRecordSentQueueIdSeparator)\(deviceId)"
    }

    static func parseCKRecordSentQueueId(_ value: String) -> (queueId: UploadQueue.ID, objectId: String, deviceId: String)? {
        let splits = value.split(separator: SyncEngine.CKRecordSentQueueIdSeparator)
        guard splits.count == 3, let queueId = UploadQueue.ID(splits[0]) else {
            return nil
        }
        return (queueId, String(splits[1]), String(splits[2]))
    }
}

private extension UploadQueue {
    private static var formatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesActualByteCount = true
        return formatter
    }

    func populateRecord(_ record: CKRecord) throws {
        record[.createByDeviceId] = deviceId
        record.lastModifiedMilliseconds = modified.millisecondsSince1970
        guard changes != .delete else {
            return
        }

        guard let realObject else { return }

        let payload = try? realObject.encodePayload()

        Logger.syncEngine.debugFile("populateRecord \(record.recordID) payload \(UploadQueue.formatter.string(fromByteCount: Int64(payload?.count ?? 0)))")

        guard let payload else {
            record.encryptedValues[.payload] = nil
            record[.payloadAsset] = nil
            return
        }

        // 大于20kb的采用CKAsset
        // CKAsset本身就会采用加密存储
        guard payload.count > 1024 * 20 else {
            record.encryptedValues[.payload] = payload
            record[.payloadAsset] = nil
            return
        }
        record.encryptedValues[.payload] = nil

        if !FileManager.default.fileExists(atPath: SyncEngine.temporaryAssetStorage.path()) {
            try FileManager.default.createDirectory(atPath: SyncEngine.temporaryAssetStorage.path(), withIntermediateDirectories: true)
        }
        let tempURL = SyncEngine.temporaryAssetStorage.appending(component: "\(UUID().uuidString).asset")
        try payload.write(to: tempURL, options: .atomic)
        let asset = CKAsset(fileURL: tempURL)
        record[.payloadAsset] = asset
    }
}

// MARK: - CKSyncEngineDelegate

@available(iOS 17, macCatalyst 17, *)
extension SyncEngine: CKSyncEngineDelegate {
    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        guard let event = SyncEngine.Event(event) else {
            return
        }

        await handleEvent(event, syncEngine: syncEngine)
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        await nextRecordZoneChangeBatch(reason: context.reason, options: context.options, syncEngine: syncEngine)
    }

    public func nextFetchChangesOptions(_ context: CKSyncEngine.FetchChangesContext, syncEngine _: CKSyncEngine) async -> CKSyncEngine.FetchChangesOptions {
        let options = context.options
        Logger.syncEngine.infoFile("Next fetch by reason: \(context.reason)")
        return options
    }
}

// MARK: - SyncEngineDelegate

@available(iOS 17, macCatalyst 17, *)
extension SyncEngine: SyncEngineDelegate {
    package func handleEvent(_ event: SyncEngine.Event, syncEngine: any SyncEngineProtocol) async {
        Logger.syncEngine.infoFile("Handling event \(event)")

        switch event {
        case let .accountChange(changeType):
            await handleAccountChange(changeType: changeType, syncEngine: syncEngine)

        case let .stateUpdate(stateSerialization):
            await handleStateUpdate(stateSerialization: stateSerialization, syncEngine: syncEngine)

        case let .fetchedDatabaseChanges(modifications, deletions):
            await handleFetchedDatabaseChanges(
                modifications: modifications,
                deletions: deletions,
                syncEngine: syncEngine,
            )

        case let .fetchedRecordZoneChanges(modifications, deletions):
            await handleFetchedRecordZoneChanges(
                modifications: modifications,
                deletions: deletions,
                syncEngine: syncEngine,
            )

        case let .sentDatabaseChanges(
            savedRecordZones,
            failedRecordZoneSaves,
            deletedRecordZoneIDs,
            failedRecordZoneDeletes,
        ):
            await handleSentDatabaseChanges(
                savedRecordZones: savedRecordZones,
                failedRecordZoneSaves: failedRecordZoneSaves,
                deletedRecordZoneIDs: deletedRecordZoneIDs,
                failedRecordZoneDeletes: failedRecordZoneDeletes,
                syncEngine: syncEngine,
            )

        case let .sentRecordZoneChanges(
            savedRecords,
            failedRecordSaves,
            deletedRecordIDs,
            failedRecordDeletes,
        ):
            await handleSentRecordZoneChanges(
                savedRecords: savedRecords,
                failedRecordSaves: failedRecordSaves,
                deletedRecordIDs: deletedRecordIDs,
                failedRecordDeletes: failedRecordDeletes,
                syncEngine: syncEngine,
            )

        case .willFetchRecordZoneChanges:
            await enqueueFetchingChanges()

        case .didFetchRecordZoneChanges:
            await dequeueFetchingChanges()

        case .willFetchChanges:
            await enqueueFetchingChanges()

        case .didFetchChanges:
            await dequeueFetchingChanges()
            // 调度下一批
            try? await scheduleUploadIfNeeded()

        case .willSendChanges:
            await enqueueSendingChanges()

        case .didSendChanges:
            await dequeueSendingChanges()
            // 调度下一批
            try? await scheduleUploadIfNeeded()

        @unknown default:
            break
        }
    }

    package func nextRecordZoneChangeBatch(
        reason: CKSyncEngine.SyncReason,
        options: CKSyncEngine.SendChangesOptions,
        syncEngine: any SyncEngineProtocol,
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        Logger.syncEngine.infoFile("Next push by reason: \(reason)")

        let scope = options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }

        // 最终提交的保存记录
        var recordsToSave: [CKRecord] = []

        // 当前 state 中待上传的删除队列项
        var realRecordIDsToDeleteSet: OrderedSet<CKRecord.ID> = []

        // 当前 state 中待上传的保存队列项
        var recordsToSaveQueueIds: [(queueId: UploadQueue.ID, recordId: CKRecord.ID)] = []
        for change in changes {
            switch change {
            case let .saveRecord(recordId):
                guard let (queueId, _, _) = SyncEngine.parseCKRecordSentQueueId(recordId.recordName) else {
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordId)])
                    continue
                }

                recordsToSaveQueueIds.append((queueId, recordId))
            case let .deleteRecord(recordId):
                realRecordIDsToDeleteSet.append(recordId)
            @unknown default:
                continue
            }
        }

        if recordsToSaveQueueIds.isEmpty, realRecordIDsToDeleteSet.isEmpty {
            return nil
        }

        // 实际从数据库中查出来的保存队列记录
        let objects = storage.pendingUploadList(queueIds: recordsToSaveQueueIds.map(\.0), queryRealObject: true)

        // 取出现存的 queueId 集合
        let existingQueueIds = Set(objects.map(\.id))

        // ✅ 找出 state 中有但数据库已无的 queueId
        let missingQueueIds = recordsToSaveQueueIds.filter { !existingQueueIds.contains($0.queueId) }

        if !missingQueueIds.isEmpty {
            // 需要从 syncEngine.state 中移除的 pending changes
            let staleChanges: [CKSyncEngine.PendingRecordZoneChange] = missingQueueIds.map {
                .saveRecord($0.recordId)
            }

            Logger.syncEngine.infoFile("Removing \(staleChanges.count) missing UploadQueue pending changes")
            syncEngine.state.remove(pendingRecordZoneChanges: staleChanges)
        }

        let deviceId = Storage.deviceId

        /// 对于同一批次保存记录，不能有重复的，所以这里去重处理
        /// 只用最新的记录
        /// ✅ Step 1: 按 ckRecordID 分组
        let groupedByRecord = Dictionary(grouping: objects, by: { $0.ckRecordID })

        /// ✅ Step 2: 对每组取 id 最大的那一条作为最终对象
        var latestObjects: [UploadQueue] = []
        var staleRecordChanges: [CKSyncEngine.PendingRecordZoneChange] = []

        for (_, group) in groupedByRecord {
            guard let latest = group.max(by: { $0.id < $1.id }) else { continue }
            latestObjects.append(latest)

            /// 旧版本 UploadQueue 的变更应被移除
            let stale = group.filter { $0.id != latest.id }
            for old in stale {
                let staleChange = CKSyncEngine.PendingRecordZoneChange.saveRecord(
                    CKRecord.ID(recordName: SyncEngine.makeCKRecordSentQueueId(
                        queueId: old.id,
                        objectId: old.objectId,
                        deviceId: deviceId,
                    ), zoneID: SyncEngine.zoneID),
                )
                staleRecordChanges.append(staleChange)
            }
        }

        /// ✅ Step 3: 从 SyncEngine state 移除旧的 PendingChanges
        if !staleRecordChanges.isEmpty {
            Logger.syncEngine.infoFile("Removing \(staleRecordChanges.count) stale old record changes")
            syncEngine.state.remove(pendingRecordZoneChanges: staleRecordChanges)
        }

        /// ✅ Step 4: 用最新对象生成 CKRecord
        for object in latestObjects {
            let recordID = CKRecord.ID(recordName: object.ckRecordID, zoneID: SyncEngine.zoneID)
            if object.changes == .delete {
                // 最新操作是删除，则不再保存，而是加入删除队列
                realRecordIDsToDeleteSet.append(recordID)
                continue
            }

            let metadata: SyncMetadata? = try? storage.findSyncMetadata(zoneName: SyncEngine.zoneID.zoneName, ownerName: SyncEngine.zoneID.ownerName, recordName: object.ckRecordID)

            let record = metadata?.lastKnownRecord ?? CKRecord(recordType: SyncEngine.recordType, recordID: recordID)

            let sentQueueId = SyncEngine.makeCKRecordSentQueueId(queueId: object.id, objectId: object.objectId, deviceId: deviceId)
            record.sentQueueId = sentQueueId
            record.lastModifiedByDeviceId = deviceId
            do {
                try object.populateRecord(record)
                recordsToSave.append(record)
            } catch {
                Logger.syncEngine.errorFile("populateRecord error \(error)")
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        }

        /// 更新为 uploading
        try? storage.pendingUploadChangeState(by: objects.map { ($0.id, .uploading) })

        let realRecordIDsToDelete = realRecordIDsToDeleteSet.elements
        if recordsToSave.isEmpty, realRecordIDsToDelete.isEmpty {
            return nil
        }

        Logger.syncEngine.infoFile("Push batch modifications \(recordsToSave.count) deletions \(realRecordIDsToDelete.count)")
        let batch = CKSyncEngine.RecordZoneChangeBatch(recordsToSave: recordsToSave, recordIDsToDelete: realRecordIDsToDelete, atomicByZone: true)
        return batch
    }

    package func nextFetchChangesOptions(
        reason: CKSyncEngine.SyncReason,
        options _: CKSyncEngine.FetchChangesOptions,
        syncEngine _: any SyncEngineProtocol,
    ) async -> CKSyncEngine.FetchChangesOptions {
        Logger.syncEngine.infoFile("Next fetch by reason: \(reason)")
        let options = CKSyncEngine.FetchChangesOptions()
        return options
    }
}

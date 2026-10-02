import ConfigurableKit
@testable import FlowDown
import Foundation
import Testing

/// Release builds use an unprefixed `ConfigurableKit.storage`, so the settings suite
/// also holds the CKSyncEngine state that Storage's SyncEngine writes to `UserDefaults.standard`.
@Suite(.serialized)
struct SettingsBackupSyncStateTests {
    private static let syncEngineStateKey = "FlowDownSyncEngineState"

    @Test
    func settingsBackupExport_unprefixedStorage_excludesSyncEngineState() throws {
        try withUnprefixedStorage { storage, suite in
            ConfigurableKit.set(value: true, forKey: LiveActivitySetting.storageKey, storage: storage)
            suite.set(Data(#"{"data":"AAAA"}"#.utf8), forKey: Self.syncEngineStateKey)

            let exportURL = try SettingsBackup.export(storage: storage)
            defer { try? FileManager.default.removeItem(at: exportURL) }

            let payload = try JSONDecoder().decode(
                BackupPayload.self,
                from: Data(contentsOf: exportURL),
            )
            let exportedKeys = Set(payload.items.map(\.key))

            #expect(exportedKeys.contains(LiveActivitySetting.storageKey))
            #expect(!exportedKeys.contains(Self.syncEngineStateKey))
        }
    }

    @Test
    func settingsBackupImport_unprefixedStorage_keepsLocalSyncEngineState() throws {
        try withUnprefixedStorage { storage, suite in
            let localState = Data(#"{"data":"LOCAL"}"#.utf8)
            suite.set(localState, forKey: Self.syncEngineStateKey)

            let importURL = try makeBackupFile(items: [
                .init(
                    key: LiveActivitySetting.storageKey,
                    data: encodedConfigurableValue(true),
                ),
                .init(
                    key: Self.syncEngineStateKey,
                    data: Data(#"{"data":"REMOTE"}"#.utf8),
                ),
            ])
            defer { try? FileManager.default.removeItem(at: importURL) }

            try SettingsBackup.importBackup(from: importURL, storage: storage)

            let restoredLiveActivity: Bool? = ConfigurableKit.value(
                forKey: LiveActivitySetting.storageKey,
                storage: storage,
            )

            #expect(restoredLiveActivity == true)
            #expect(suite.data(forKey: Self.syncEngineStateKey) == localState)
        }
    }
}

private extension SettingsBackupSyncStateTests {
    struct BackupPayload: Codable {
        struct Item: Codable {
            let key: String
            let data: Data
        }

        let formatVersion: Int
        let createdAt: Date
        let items: [Item]
    }

    func withUnprefixedStorage(
        _ body: (UserDefaultKeyValueStorage, UserDefaults) throws -> Void,
    ) throws {
        let suiteName = "FlowDownUnitTests.SettingsBackupSyncState.\(UUID().uuidString)"
        let suite = try #require(UserDefaults(suiteName: suiteName))
        suite.removePersistentDomain(forName: suiteName)
        defer { suite.removePersistentDomain(forName: suiteName) }

        try body(UserDefaultKeyValueStorage(suite: suite), suite)
    }

    func makeBackupFile(items: [BackupPayload.Item]) throws -> URL {
        let payload = BackupPayload(
            formatVersion: 1,
            createdAt: Date(timeIntervalSince1970: 1234),
            items: items,
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsBackupSyncState-\(UUID().uuidString)")
            .appendingPathExtension("json")
        try JSONEncoder().encode(payload).write(to: url, options: .atomic)
        return url
    }

    func encodedConfigurableValue(_ value: some Codable) throws -> Data {
        let scratchSuiteName = "FlowDownUnitTests.SettingsBackupSyncState.Encode.\(UUID().uuidString)"
        let scratchSuite = try #require(UserDefaults(suiteName: scratchSuiteName))
        scratchSuite.removePersistentDomain(forName: scratchSuiteName)
        defer { scratchSuite.removePersistentDomain(forName: scratchSuiteName) }

        let storage = UserDefaultKeyValueStorage(suite: scratchSuite)
        let key = "encoded-value"
        ConfigurableKit.set(value: value, forKey: key, storage: storage)
        return try #require(storage.value(forKey: key))
    }
}

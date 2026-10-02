import Combine
import ConfigurableKit
@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct SettingsBackupTests {
    @Test
    func `export rejects unsupported storage backends`() {
        expectSettingsBackupError(.unsupportedStorage) {
            _ = try SettingsBackup.export(storage: UnsupportedKeyValueStorage())
        }
    }

    @Test
    func `export rejects empty backups`() throws {
        try withIsolatedStorage { storage, _ in
            expectSettingsBackupError(.emptyBackup) {
                _ = try SettingsBackup.export(storage: storage)
            }
        }
    }

    @Test
    func `export keeps only configurable values and normalizes prefixed keys`() throws {
        try withIsolatedStorage(prefix: "settings.") { storage, suite in
            ConfigurableKit.set(value: true, forKey: LiveActivitySetting.storageKey, storage: storage)
            ConfigurableKit.set(value: false, forKey: EditorBehavior.compressImageStorageKey, storage: storage)

            suite.set("ignore", forKey: "settings.plain-string")
            suite.set(Data("bad".utf8), forKey: "settings.invalid-data")
            suite.set(Data("bad".utf8), forKey: "outside-prefix")

            let exportURL = try SettingsBackup.export(storage: storage)
            defer { try? FileManager.default.removeItem(at: exportURL) }

            let payload = try decodeBackupPayload(at: exportURL)
            let exportedKeys = Set(payload.items.map(\.key))

            #expect(payload.formatVersion == 1)
            #expect(exportedKeys == Set([
                LiveActivitySetting.storageKey,
                EditorBehavior.compressImageStorageKey,
            ]))
            #expect(payload.items.count == 2)
            #expect(storage.value(forKey: LiveActivitySetting.storageKey) != nil)
        }
    }

    @Test
    func `import clears stale configurable values before restoring backup`() throws {
        try withIsolatedStorage(prefix: "settings.") { storage, _ in
            ConfigurableKit.set(value: false, forKey: LiveActivitySetting.storageKey, storage: storage)
            ConfigurableKit.set(value: true, forKey: EditorBehavior.pasteAsFileStorageKey, storage: storage)

            let importURL = try makeBackupFile(items: [
                .init(
                    key: LiveActivitySetting.storageKey,
                    data: encodedConfigurableValue(true),
                ),
            ])
            defer { try? FileManager.default.removeItem(at: importURL) }

            try SettingsBackup.importBackup(from: importURL, storage: storage)

            let restoredLiveActivity: Bool? = ConfigurableKit.value(
                forKey: LiveActivitySetting.storageKey,
                storage: storage
            )
            let stalePasteAsFile: Bool? = ConfigurableKit.value(
                forKey: EditorBehavior.pasteAsFileStorageKey,
                storage: storage
            )

            #expect(restoredLiveActivity == true)
            #expect(stalePasteAsFile == nil)
        }
    }

    @Test
    func `import rejects incompatible backup versions`() throws {
        try withIsolatedStorage { storage, _ in
            let importURL = try makeBackupFile(formatVersion: 999, items: [])
            defer { try? FileManager.default.removeItem(at: importURL) }

            expectSettingsBackupError(.invalidBackup) {
                try SettingsBackup.importBackup(from: importURL, storage: storage)
            }
        }
    }

    @Test
    func `import rejects corrupted backup payloads`() throws {
        try withIsolatedStorage { storage, _ in
            let importURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("SettingsBackup-\(UUID().uuidString)")
                .appendingPathExtension("json")
            try Data("not-json".utf8).write(to: importURL, options: .atomic)
            defer { try? FileManager.default.removeItem(at: importURL) }

            var didThrow = false
            do {
                try SettingsBackup.importBackup(from: importURL, storage: storage)
            } catch {
                didThrow = true
            }

            #expect(didThrow)
        }
    }
}

private extension SettingsBackupTests {
    struct BackupPayload: Codable {
        struct Item: Codable {
            let key: String
            let data: Data
        }

        let formatVersion: Int
        let createdAt: Date
        let items: [Item]
    }

    func withIsolatedStorage(
        prefix: String = "settings.",
        _ body: (UserDefaultKeyValueStorage, UserDefaults) throws -> Void,
    ) throws {
        let suiteName = "FlowDownUnitTests.SettingsBackup.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: suiteName)!
        suite.removePersistentDomain(forName: suiteName)

        let storage = UserDefaultKeyValueStorage(suite: suite, prefix: prefix)
        defer {
            suite.removePersistentDomain(forName: suiteName)
        }

        try body(storage, suite)
    }

    func decodeBackupPayload(at url: URL) throws -> BackupPayload {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(BackupPayload.self, from: data)
    }

    func makeBackupFile(
        formatVersion: Int = 1,
        items: [BackupPayload.Item],
    ) throws -> URL {
        let payload = BackupPayload(
            formatVersion: formatVersion,
            createdAt: Date(timeIntervalSince1970: 1234),
            items: items,
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SettingsBackup-\(UUID().uuidString)")
            .appendingPathExtension("json")
        let data = try JSONEncoder().encode(payload)
        try data.write(to: url, options: .atomic)
        return url
    }

    func encodedConfigurableValue(_ value: some Codable) throws -> Data {
        let scratchSuiteName = "FlowDownUnitTests.SettingsBackup.Encode.\(UUID().uuidString)"
        let scratchSuite = UserDefaults(suiteName: scratchSuiteName)!
        scratchSuite.removePersistentDomain(forName: scratchSuiteName)
        defer { scratchSuite.removePersistentDomain(forName: scratchSuiteName) }

        let storage = UserDefaultKeyValueStorage(suite: scratchSuite)
        let key = "encoded-value"
        ConfigurableKit.set(value: value, forKey: key, storage: storage)

        guard let data = storage.value(forKey: key) else {
            throw EncodingError.invalidValue(
                value,
                .init(codingPath: [], debugDescription: "Unable to encode configurable value."),
            )
        }
        return data
    }

    func expectSettingsBackupError(
        _ expected: SettingsBackupError,
        performing operation: () throws -> Void,
    ) {
        do {
            try operation()
            Issue.record("Expected \(expected.caseName) error.")
        } catch let error as SettingsBackupError {
            #expect(error.caseName == expected.caseName)
        } catch {
            Issue.record("Expected SettingsBackupError, got \(error).")
        }
    }
}

private extension SettingsBackupError {
    var caseName: String {
        switch self {
        case .unsupportedStorage:
            "unsupportedStorage"
        case .emptyBackup:
            "emptyBackup"
        case .invalidBackup:
            "invalidBackup"
        }
    }
}

private final class UnsupportedKeyValueStorage: KeyValueStorage {
    static let valueUpdatePublisher: PassthroughSubject<(String, Data?), Never> = .init()

    func value(forKey _: String) -> Data? {
        nil
    }

    func setValue(_: Data?, forKey _: String) {}
}

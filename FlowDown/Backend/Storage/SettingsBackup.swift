import ConfigurableKit
import Foundation

enum SettingsBackupError: LocalizedError {
    case unsupportedStorage
    case emptyBackup
    case invalidBackup

    var errorDescription: String? {
        switch self {
        case .unsupportedStorage:
            String(localized: "Settings backup is only supported when using UserDefaults storage.")
        case .emptyBackup:
            String(localized: "No configurable settings were found to export.")
        case .invalidBackup:
            String(localized: "The selected settings backup is invalid or from an incompatible version.")
        }
    }
}

private struct SettingsBackupPayload: Codable {
    struct Item: Codable {
        let key: String
        let data: Data
    }

    static let version = 1

    let formatVersion: Int
    let createdAt: Date
    let items: [Item]
}

enum SettingsBackup {
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder = JSONDecoder()

    static func export(storage: KeyValueStorage = ConfigurableKit.storage) throws -> URL {
        let storage = try userDefaultsStorage(from: storage)
        let items = try collectConfigurableItems(from: storage)
        guard !items.isEmpty else { throw SettingsBackupError.emptyBackup }

        let payload = SettingsBackupPayload(
            formatVersion: SettingsBackupPayload.version,
            createdAt: Date(),
            items: items,
        )

        let data = try encoder.encode(payload)
        let outputURL = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(
                String(
                    format: String(localized: "FlowDown Settings Backup %@"),
                    exportTimestampFormatter.string(from: Date()),
                ),
            )
            .appendingPathExtension("json")
        try data.write(to: outputURL, options: .atomic)
        return outputURL
    }

    static func importBackup(from url: URL, storage: KeyValueStorage = ConfigurableKit.storage) throws {
        let storage = try userDefaultsStorage(from: storage)
        let data = try Data(contentsOf: url)
        let payload = try decoder.decode(SettingsBackupPayload.self, from: data)
        guard payload.formatVersion == SettingsBackupPayload.version else {
            throw SettingsBackupError.invalidBackup
        }

        let existingItems = try collectConfigurableItems(from: storage)
        for key in existingItems.map(\.key) {
            storage.setValue(nil, forKey: key)
        }

        for item in payload.items {
            storage.setValue(item.data, forKey: item.key)
        }
    }
}

private extension SettingsBackup {
    static func userDefaultsStorage(from storage: KeyValueStorage) throws -> UserDefaultKeyValueStorage {
        guard let storage = storage as? UserDefaultKeyValueStorage else {
            throw SettingsBackupError.unsupportedStorage
        }
        return storage
    }

    static func collectConfigurableItems(from storage: UserDefaultKeyValueStorage) throws -> [SettingsBackupPayload.Item] {
        let suite = storage.exposedSuite
        let prefix = storage.exposedPrefix
        let dictionary = suite.dictionaryRepresentation()

        var items: [SettingsBackupPayload.Item] = []
        for (storedKey, value) in dictionary {
            guard let data = value as? Data else { continue }
            guard isConfigurableValue(data) else { continue }
            guard let key = normalize(storedKey: storedKey, prefix: prefix) else { continue }
            items.append(.init(key: key, data: data))
        }
        return items
    }

    static func normalize(storedKey: String, prefix: String?) -> String? {
        guard let prefix, !prefix.isEmpty else { return storedKey }
        guard storedKey.hasPrefix(prefix) else { return nil }
        return String(storedKey.dropFirst(prefix.count))
    }

    static func isConfigurableValue(_ data: Data) -> Bool {
        (try? decoder.decode(ConfigurableKitAnyCodable.self, from: data)) != nil
    }
}

private extension UserDefaultKeyValueStorage {
    var exposedSuite: UserDefaults {
        Mirror(reflecting: self).descendant("suite") as? UserDefaults ?? .standard
    }

    var exposedPrefix: String? {
        Mirror(reflecting: self).descendant("prefix") as? String
    }
}

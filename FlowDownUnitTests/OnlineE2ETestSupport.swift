@testable import FlowDown
import Foundation
@testable import Storage

enum OnlineE2ETestSupport {
    static let enableFlag = "FLOWDOWN_ENABLE_E2E"
    static let apiKeyName = "OPENROUTER_API_KEY"
    static let configurationPathName = "FLOWDOWN_E2E_FDMODEL_PATH"
    private static let supportDirectoryPathName = "FLOWDOWN_E2E_SUPPORT_PATH"
    private static let defaultSupportDirectoryPath = "/tmp/flowdown-online-e2e"
    private static let apiKeyFileName = "openrouter.sk"
    private static let enableMarkerFileName = "flowdown_e2e_enabled"
    private static let configurationPathFileName = "flowdown_e2e_fdmodel_path"

    static var isEnabled: Bool {
        guard isExecutionEnabled else { return false }
        guard loadAPIKey() != nil else { return false }
        return (try? configurationURL()) != nil
    }

    static var isExecutionEnabled: Bool {
        let env = ProcessInfo.processInfo.environment
        if env[enableFlag] == "1" {
            return true
        }

        return FileManager.default.fileExists(atPath: enableMarkerURL().path)
    }

    static func configurationURL(file: StaticString = #filePath) throws -> URL {
        let env = ProcessInfo.processInfo.environment
        if let explicitPath = env[configurationPathName], !explicitPath.isEmpty {
            return URL(fileURLWithPath: explicitPath)
        }

        if
            let explicitPath = try? String(contentsOf: configurationPathURL(), encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !explicitPath.isEmpty
        {
            return URL(fileURLWithPath: explicitPath)
        }

        let repositoryRoot = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot,
            includingPropertiesForKeys: nil,
        )
        .filter { $0.pathExtension == ModelManager.flowdownModelConfigurationExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let selected = candidates.first else {
            throw NSError(
                domain: "OnlineE2ETestSupport",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "No root .fdmodel file found."],
            )
        }
        return selected
    }

    static func loadAPIKey(named: String = apiKeyName) -> String? {
        if let value = ProcessInfo.processInfo.environment[named], !value.isEmpty {
            return value
        }

        let content = (try? String(contentsOf: apiKeyURL(), encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let content, !content.isEmpty else {
            return nil
        }
        return content
    }

    static func runtimeCloudModel() throws -> CloudModel {
        let data = try Data(contentsOf: configurationURL())
        let decoder = PropertyListDecoder()
        let model = try decoder.decode(CloudModel.self, from: data)

        guard let apiKey = loadAPIKey() else {
            throw NSError(
                domain: "OnlineE2ETestSupport",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "OPENROUTER_API_KEY is not configured."],
            )
        }

        model.update(\.deviceId, to: Storage.deviceId)
        model.update(\.objectId, to: UUID().uuidString)
        model.update(\.token, to: apiKey)
        model.update(\.removed, to: false)
        let now = Date.now
        model.update(\.creation, to: now)
        model.update(\.modified, to: now)
        return model
    }

    private static func supportDirectoryURL() -> URL {
        let env = ProcessInfo.processInfo.environment
        let path = env[supportDirectoryPathName] ?? defaultSupportDirectoryPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private static func apiKeyURL() -> URL {
        supportDirectoryURL()
            .appendingPathComponent(apiKeyFileName)
    }

    private static func enableMarkerURL() -> URL {
        supportDirectoryURL()
            .appendingPathComponent(enableMarkerFileName)
    }

    private static func configurationPathURL() -> URL {
        supportDirectoryURL()
            .appendingPathComponent(configurationPathFileName)
    }
}

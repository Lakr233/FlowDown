@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Storage

enum OnlineE2ETestSupport {
    static let enableFlag = "FLOWDOWN_ENABLE_E2E"
    static let endpointEnvName = "FLOWDOWN_ONLINE_E2E_ENDPOINT"
    static let modelIDEnvName = "FLOWDOWN_ONLINE_E2E_MODEL_ID"

    private static let runtimeDirectory = URL(fileURLWithPath: "/tmp/flowdown-online-e2e", isDirectory: true)
    private static let runtimeEndpointFilename = "flowdown-online-e2e.endpoint"
    private static let localToken = "flowdown-local-e2e-token"
    private static let localModelIdentifier = "flowdown-local-e2e"

    /// Convenience flag covering the default (chat completions) API path.
    static var isEnabled: Bool {
        isEnabled(for: .chatCompletions)
    }

    static func isEnabled(for responseFormat: CloudModel.ResponseFormat) -> Bool {
        isEnabled(for: responseFormat, in: ProcessInfo.processInfo.environment)
    }

    static func isEnabled(
        for responseFormat: CloudModel.ResponseFormat,
        in environment: [String: String],
    ) -> Bool {
        guard isExecutionEnabled(in: environment) else { return false }
        return runtimeEndpoint(for: responseFormat, in: environment) != nil
    }

    static var isExecutionEnabled: Bool {
        isExecutionEnabled(in: ProcessInfo.processInfo.environment)
    }

    static func isExecutionEnabled(in environment: [String: String]) -> Bool {
        if let explicitFlag = environment[enableFlag] {
            return explicitFlag == "1"
        }
        if FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("flowdown_e2e_enabled").path) {
            return true
        }
        return false
    }

    static var responseFormats: [CloudModel.ResponseFormat] {
        responseFormats(in: ProcessInfo.processInfo.environment)
    }

    static func responseFormats(in environment: [String: String]) -> [CloudModel.ResponseFormat] {
        guard isEnabled(for: .chatCompletions, in: environment) else { return [] }
        return [.chatCompletions]
    }

    static func runtimeCloudModel(responseFormat: CloudModel.ResponseFormat = .chatCompletions) throws -> CloudModel {
        CloudModel(
            deviceId: Storage.deviceId,
            model_identifier: runtimeModelIdentifier(in: ProcessInfo.processInfo.environment),
            model_list_endpoint: responseFormat.defaultModelListEndpoint,
            creation: .now,
            endpoint: try resolveEndpoint(for: responseFormat, in: ProcessInfo.processInfo.environment),
            token: localToken,
            headers: [:],
            bodyFields: "",
            context: .long_100k,
            capabilities: [.tool],
            comment: "Local captured fixture server for online E2E tests",
            name: "Local E2E Fixture",
            response_format: responseFormat,
        )
    }

    static func makeCompletionsClient() throws -> RemoteCompletionsChatClient {
        let endpoint = splitEndpoint(try resolveEndpoint(
            for: .chatCompletions,
            in: ProcessInfo.processInfo.environment
        ))
        return RemoteCompletionsChatClient(
            model: runtimeModelIdentifier(in: ProcessInfo.processInfo.environment),
            baseURL: endpoint.baseURL,
            path: endpoint.path,
            apiKey: localToken,
        )
    }

    static func makeResponsesClient() throws -> RemoteResponsesChatClient {
        throw NSError(
            domain: "OnlineE2ETestSupport",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Local online E2E fixtures support chat completions only.",
            ],
        )
    }

    static func runtimeEndpoint(
        for responseFormat: CloudModel.ResponseFormat,
        in environment: [String: String],
    ) -> String? {
        guard responseFormat == .chatCompletions else { return nil }
        if let endpoint = trimmedNonEmpty(environment[endpointEnvName]) {
            return endpoint
        }
        if environment.keys.contains(enableFlag) {
            return nil
        }
        let endpointURL = runtimeDirectory.appendingPathComponent(runtimeEndpointFilename)
        guard let endpoint = try? String(contentsOf: endpointURL, encoding: .utf8) else {
            return nil
        }
        return trimmedNonEmpty(endpoint)
    }

    private static func resolveEndpoint(
        for responseFormat: CloudModel.ResponseFormat,
        in environment: [String: String],
    ) throws -> String {
        guard let endpoint = runtimeEndpoint(for: responseFormat, in: environment) else {
            throw NSError(
                domain: "OnlineE2ETestSupport",
                code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey: "Local online E2E endpoint is not configured.",
                ],
            )
        }
        return endpoint
    }

    private static func runtimeModelIdentifier(in environment: [String: String]) -> String {
        trimmedNonEmpty(environment[modelIDEnvName]) ?? localModelIdentifier
    }

    private static func splitEndpoint(_ endpoint: String) -> (baseURL: String?, path: String?) {
        guard let components = URLComponents(string: endpoint), components.host != nil else {
            return (endpoint.isEmpty ? nil : endpoint, endpoint.isEmpty ? nil : "/")
        }
        var base = URLComponents()
        base.scheme = components.scheme
        base.host = components.host
        base.port = components.port
        let baseURL = base.string
        var pathComponents = URLComponents()
        pathComponents.path = components.path.isEmpty ? "/" : components.path
        pathComponents.queryItems = components.queryItems
        pathComponents.fragment = components.fragment
        let path = pathComponents.string ?? components.path
        return (baseURL, path)
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

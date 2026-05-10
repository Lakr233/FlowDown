@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Storage

enum OnlineE2ETestSupport {
    static let enableFlag = "FLOWDOWN_ENABLE_E2E"
    static let tokenEnvName = "FLOWDOWN_ONLINE_E2E_TOKEN"
    static let endpointEnvName = "FLOWDOWN_ONLINE_E2E_ENDPOINT"
    static let responsesEndpointEnvName = "FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES"

    // Endpoint and token are provided via environment variables (backed by
    // GitHub secrets in CI or a local ~/.testing file). The model identifier,
    // headers, body fields, and capabilities below track the exported
    // kimi-k2p5-turbo .fdmodel but can still be overridden via env.
    private static let embeddedFixture = EmbeddedCloudModelFixture(
        modelIdentifier: "kimi-k2p6-turbo",
        headers: [
            "HTTP-Referer": "https://flowdown.ai/",
            "X-Title": "FlowDown",
        ],
        bodyFields: "",
        context: .long_200k,
        capabilities: [.visual, .developerRole, .tool],
        comment: "online-e2e",
        name: "Embedded Online E2E Model",
    )

    /// Convenience flag covering the default (chat completions) API path.
    static var isEnabled: Bool {
        isEnabled(for: .chatCompletions)
    }

    static func isEnabled(for responseFormat: CloudModel.ResponseFormat) -> Bool {
        guard isExecutionEnabled else { return false }
        let environment = ProcessInfo.processInfo.environment
        guard runtimeToken(in: environment) != nil else { return false }
        return runtimeEndpoint(for: responseFormat, in: environment) != nil
    }

    static var isExecutionEnabled: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment[enableFlag] == "0" {
            return false
        }
        return true
    }

    static func runtimeCloudModel(responseFormat: CloudModel.ResponseFormat = .chatCompletions) throws -> CloudModel {
        let environment = ProcessInfo.processInfo.environment
        let token = try resolveToken(in: environment)
        let endpoint = try resolveEndpoint(for: responseFormat, in: environment)

        let fixture = embeddedFixture.overriding(with: environment)

        return CloudModel(
            deviceId: Storage.deviceId,
            model_identifier: fixture.modelIdentifier,
            model_list_endpoint: responseFormat.defaultModelListEndpoint,
            creation: .now,
            endpoint: endpoint,
            token: token,
            headers: fixture.headers,
            bodyFields: fixture.bodyFields,
            context: fixture.context,
            capabilities: fixture.capabilities,
            comment: fixture.comment,
            name: fixture.name,
            response_format: responseFormat,
        )
    }

    static func makeCompletionsClient() throws -> RemoteCompletionsChatClient {
        let environment = ProcessInfo.processInfo.environment
        let token = try resolveToken(in: environment)
        let endpoint = try resolveEndpoint(for: .chatCompletions, in: environment)
        let (baseURL, path) = splitEndpoint(endpoint)
        let fixture = embeddedFixture.overriding(with: environment)
        return RemoteCompletionsChatClient(
            model: fixture.modelIdentifier,
            baseURL: baseURL,
            path: path,
            apiKey: token,
            additionalHeaders: fixture.headers,
        )
    }

    static func makeResponsesClient() throws -> RemoteResponsesChatClient {
        let environment = ProcessInfo.processInfo.environment
        let token = try resolveToken(in: environment)
        let endpoint = try resolveEndpoint(for: .responses, in: environment)
        let (baseURL, path) = splitEndpoint(endpoint)
        let fixture = embeddedFixture.overriding(with: environment)
        return RemoteResponsesChatClient(
            model: fixture.modelIdentifier,
            baseURL: baseURL,
            path: path,
            apiKey: token,
            additionalHeaders: fixture.headers,
        )
    }

    // MARK: - Resolution

    private static func resolveToken(in environment: [String: String]) throws -> String {
        guard let token = runtimeToken(in: environment) else {
            throw NSError(
                domain: "OnlineE2ETestSupport",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: """
                    No online E2E API token was found. Set FLOWDOWN_ONLINE_E2E_TOKEN, or place the token in ~/.testing/flowdown-online-e2e.token.
                    """,
                ],
            )
        }
        return token
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
                    NSLocalizedDescriptionKey: """
                    No online E2E endpoint was configured for \(responseFormat). Set FLOWDOWN_ONLINE_E2E_ENDPOINT (and optionally FLOWDOWN_ONLINE_E2E_ENDPOINT_RESPONSES), or place the URL in ~/.testing/flowdown-online-e2e.endpoint.
                    """,
                ],
            )
        }
        return endpoint
    }

    private static func runtimeToken(in environment: [String: String]) -> String? {
        if let token = trimmedNonEmpty(environment[tokenEnvName]) {
            return token
        }
        return secretFromFiles(named: "flowdown-online-e2e.token")
    }

    private static func runtimeEndpoint(
        for responseFormat: CloudModel.ResponseFormat,
        in environment: [String: String],
    ) -> String? {
        switch responseFormat {
        case .chatCompletions:
            return primaryChatCompletionsEndpoint(in: environment)
        case .responses:
            if let explicit = trimmedNonEmpty(environment[responsesEndpointEnvName]) {
                return explicit
            }
            if let fileValue = secretFromFiles(named: "flowdown-online-e2e.endpoint.responses") {
                return fileValue
            }
            if let base = primaryChatCompletionsEndpoint(in: environment) {
                return deriveResponsesEndpoint(from: base)
            }
            return nil
        }
    }

    private static func primaryChatCompletionsEndpoint(in environment: [String: String]) -> String? {
        if let endpoint = trimmedNonEmpty(environment[endpointEnvName]) {
            return endpoint
        }
        return secretFromFiles(named: "flowdown-online-e2e.endpoint")
    }

    /// Swaps the trailing `/chat/completions` segment for `/responses` so a single
    /// chat-completions secret can cover both APIs when the provider uses the
    /// standard path layout.
    private static func deriveResponsesEndpoint(from endpoint: String) -> String? {
        guard var components = URLComponents(string: endpoint) else { return nil }
        var path = components.path
        if path.hasSuffix("/chat/completions") {
            path = String(path.dropLast("/chat/completions".count)) + "/responses"
        } else if path.hasSuffix("/chat/completions/") {
            path = String(path.dropLast("/chat/completions/".count)) + "/responses"
        } else {
            return nil
        }
        components.path = path
        return components.string
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

    private static func secretFromFiles(named filename: String) -> String? {
        for url in secretFileCandidates(named: filename) {
            guard let value = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }
            if let value = trimmedNonEmpty(value) {
                return value
            }
        }
        return nil
    }

    private static func secretFileCandidates(named filename: String) -> [URL] {
        let currentHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let hostHome = URL(fileURLWithPath: "/Users", isDirectory: true)
            .appendingPathComponent(NSUserName(), isDirectory: true)

        var seenPaths = Set<String>()
        return [currentHome, hostHome]
            .map { $0.appendingPathComponent(".testing").appendingPathComponent(filename) }
            .filter { seenPaths.insert($0.standardizedFileURL.path).inserted }
    }

    private static func trimmedNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private struct EmbeddedCloudModelFixture {
    let modelIdentifier: String
    let headers: [String: String]
    let bodyFields: String
    let context: ModelContextLength
    let capabilities: Set<ModelCapabilities>
    let comment: String
    let name: String

    func overriding(with environment: [String: String]) -> Self {
        Self(
            modelIdentifier: environment["FLOWDOWN_ONLINE_E2E_MODEL_ID"] ?? modelIdentifier,
            headers: headers,
            bodyFields: environment["FLOWDOWN_ONLINE_E2E_BODY_FIELDS"] ?? bodyFields,
            context: context,
            capabilities: capabilities,
            comment: comment,
            name: name,
        )
    }
}

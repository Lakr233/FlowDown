//
//  PromptCacheStabilityTests.swift
//  FlowDownUnitTests
//
//  Providers reuse a cached prompt only for an identical prefix. These tests
//  serialize real request bodies, through the same `resolve` and
//  `makeURLRequest` steps the clients' `streamingChat` takes, and check that
//  only the final user message varies between requests.
//

@testable import ChatClientKit
@testable import FlowDown
import Foundation
import MCP
import Testing

@Suite(.serialized)
struct PromptCacheStabilityTests {
    enum API: String, CaseIterable {
        case completions
        case responses
    }

    init() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
    }

    @Test(arguments: API.allCases)
    func `same input serializes to identical bytes`(_ api: API) async throws {
        let first = try await serializedBody(api, userText: "What should I pack?", date: Self.morning)
        let second = try await serializedBody(
            api,
            userText: "What should I pack?",
            date: Self.morning,
            mcpTools: Array(Self.mcpTools.reversed()),
        )
        #expect(first == second)
    }

    @Test(arguments: API.allCases)
    func `changing only the date keeps everything outside the context identical`(_ api: API) async throws {
        let morning = try await serializedBody(api, userText: "What should I pack?", date: Self.morning)
        let evening = try await serializedBody(api, userText: "What should I pack?", date: Self.evening)
        #expect(morning != evening)

        let contextStart = try #require(morning.range(of: Data(Self.finalMessageOpening.utf8))).lowerBound
        let contextEnd = try #require(
            morning.range(of: Data(ConversationSystemPromptBuilder.contextSectionClosing.utf8)),
        ).upperBound
        // Every byte before the final user message matches, and so does
        // everything after its context part (Responses sorts `instructions`
        // and `tools` after `input`).
        #expect(commonPrefixLength(morning, evening) > contextStart)
        #expect(commonSuffixLength(morning, evening) >= morning.count - contextEnd)
    }

    @Test(arguments: API.allCases)
    func `changing only the user message keeps everything before it identical`(_ api: API) async throws {
        let first = try await serializedBody(api, userText: "What should I pack?", date: Self.morning)
        let second = try await serializedBody(api, userText: "Is it going to rain?", date: Self.morning)
        #expect(first != second)

        let userText = try #require(first.range(of: Data("What should I pack?".utf8)))
        #expect(commonPrefixLength(first, second) >= userText.lowerBound)
        #expect(commonSuffixLength(first, second) >= first.count - userText.upperBound)
    }

    @Test(arguments: API.allCases)
    func `next turn replays the previous request up to its final user message`(_ api: API) async throws {
        let firstTurn = try await serializedBody(api, userText: "What should I pack?", date: Self.morning)
        let secondTurn = try await serializedBody(
            api,
            history: Self.history + [
                .user(content: .text("What should I pack?")),
                .assistant(content: .text("A raincoat.")),
            ],
            userText: "Is it going to rain?",
            date: Self.evening,
        )

        let finalMessageStart = try #require(firstTurn.range(of: Data(Self.finalMessageOpening.utf8))).lowerBound
        #expect(commonPrefixLength(firstTurn, secondTurn) >= finalMessageStart)
    }

    @Test
    func `variable context stays out of the system prompt and instructions`() async throws {
        let completions = try jsonObject(
            await serializedBody(.completions, userText: "What should I pack?", date: Self.morning),
        )
        let messages = try #require(completions["messages"] as? [[String: Any]])
        let systemMessages = messages.filter { $0["role"] as? String == "system" }
        #expect(systemMessages.count == 1)
        #expect(messages.first?["role"] as? String == "system")
        let system = try #require(systemMessages.first?["content"] as? String)
        #expect(system.hasPrefix(Self.storedPrompt))
        #expect(system.contains("store_memory"))
        for variable in [Self.morning, "Proactive Memory Context", "Recent conversation context", "Web Search Mode:"] {
            #expect(!system.contains(variable))
        }
        let finalParts = try #require(messages.last?["content"] as? [[String: Any]])
        #expect(finalParts.count == 2)
        #expect((finalParts[0]["text"] as? String)?.contains(Self.morning) == true)
        #expect(finalParts[1]["text"] as? String == "What should I pack?")

        let responses = try jsonObject(
            await serializedBody(.responses, userText: "What should I pack?", date: Self.morning),
        )
        let instructions = try #require(responses["instructions"] as? String)
        #expect(instructions == system)
    }

    @Test(arguments: API.allCases)
    func `tool list keeps registry order then sorted MCP tools`(_ api: API) throws {
        let shuffled = try serializedTools(api, mcpTools: [
            Self.mcpTools[3], Self.mcpTools[0], Self.mcpTools[2], Self.mcpTools[1],
        ])
        let ordered = try serializedTools(api, mcpTools: Self.mcpTools)
        #expect(shuffled == ordered)

        let tools = try #require(jsonObject(ordered)["tools"] as? [[String: Any]])
        let names = tools.compactMap { tool in
            // Chat Completions nests the name under `function`, Responses does not.
            ((tool["function"] as? [String: Any])?["name"] as? String) ?? (tool["name"] as? String)
        }
        let builtInTools: [any ModelTool] = [MTWebScraperTool(), MTRecallMemoryTool()]
        let builtIns = builtInTools.compactMap(\.definition.functionName)
        #expect(names == builtIns + ["fetch_page", "search", "add_event", "list_events"])
    }

    @Test
    func `MCP tools sort by server and then tool name`() {
        let expected = Self.mcpTools.map { "\($0.serverName)/\($0.name)" }
        let permutations: [[MCPToolInfo]] = [
            Self.mcpTools,
            Array(Self.mcpTools.reversed()),
            [Self.mcpTools[2], Self.mcpTools[0], Self.mcpTools[3], Self.mcpTools[1]],
        ]
        for permutation in permutations {
            let sorted = MCPService.sortedForListing(permutation)
            #expect(sorted.map { "\($0.serverName)/\($0.name)" } == expected)
        }
    }
}

// MARK: - Fixtures

private extension PromptCacheStabilityTests {
    static let morning = "2026-11-11 Wednesday (Asia/Shanghai, GMT+08:00)"
    static let evening = "2026-11-12 Thursday (Asia/Shanghai, GMT+08:00)"
    static let storedPrompt = "You are a helpful assistant. Chat was created at 2026-11-11 09:41 Wednesday GMT+08:00."

    /// How a final user message carrying context starts once encoded with
    /// sorted keys, in both APIs.
    static let finalMessageOpening = "{\"content\":[{\"text\":\""
        + ConversationSystemPromptBuilder.contextSectionOpening

    static var history: [ChatRequestBody.Message] { [
        .system(content: .text(storedPrompt)),
        .user(content: .text("Plan a weekend in Kyoto.")),
        .assistant(content: nil, toolCalls: [
            .init(id: "call_1", function: .init(name: "web_scraper", arguments: #"{"url":"https://example.com/kyoto"}"#)),
        ]),
        .tool(content: .text("Kyoto travel guide"), toolCallID: "call_1"),
        .assistant(content: .text("Here is a plan.")),
    ] }

    /// Already in listing order: server name, then tool name.
    static var mcpTools: [MCPToolInfo] { [
        mcpTool("fetch_page", server: "alpha.example.com", properties: ["url", "max_length", "format"]),
        mcpTool("search", server: "alpha.example.com", properties: ["query", "limit"]),
        mcpTool("add_event", server: "zeta.example.com", properties: ["title", "start", "end", "all_day"]),
        mcpTool("list_events", server: "zeta.example.com", properties: ["from", "to"]),
    ] }

    static func mcpTool(_ name: String, server: String, properties: [String]) -> MCPToolInfo {
        var schemaProperties: [String: Value] = [:]
        for property in properties {
            schemaProperties[property] = .object(["type": .string("string"), "description": .string(property)])
        }
        return MCPToolInfo(
            name: name,
            description: "\(name) on \(server)",
            inputSchema: .object([
                "type": .string("object"),
                "properties": .object(schemaProperties),
                "required": .array(properties.map { .string($0) }),
            ]),
            serverID: "server-\(server)",
            serverName: server,
        )
    }

    func dependencies(date: String) -> ConversationSystemPromptBuilder.Dependencies {
        .init(
            enabledTools: [MTWebScraperTool(), MTRecallMemoryTool()],
            proactiveMemoryScope: .recent30,
            searchSensitivity: .balanced,
            runtimeSystemInfoProvider: { modelName in
                ConversationSystemPromptBuilder.runtimeSystemInfo(modelName: modelName, date: date)
            },
            proactiveMemoryContextProvider: {
                "Proactive Memory Context\n1. User prefers metric units."
            },
            recentConversationContextProvider: { _ in
                "Recent conversation context (for background awareness only):\n1. Trip planning."
            },
        )
    }

    func toolDefinitions(mcpTools: [MCPToolInfo]) -> [ChatRequestBody.Tool] {
        let mcp = MCPService.sortedForListing(mcpTools).map {
            MCPTool(toolInfo: $0, mcpService: MCPService.shared) as any ModelTool
        }
        let builtIns: [any ModelTool] = [MTWebScraperTool(), MTRecallMemoryTool()]
        return ModelToolSet(tools: builtIns + mcp).definitions ?? []
    }

    func serializedBody(
        _ api: API,
        history: [ChatRequestBody.Message] = Self.history,
        userText: String,
        date: String,
        mcpTools: [MCPToolInfo] = Self.mcpTools,
    ) async throws -> Data {
        var messages = history
        await ConversationSystemPromptBuilder.appendMessages(
            to: &messages,
            input: .init(
                userText: userText,
                modelName: "test-model",
                modelWillExecuteTools: true,
                webSearchEnabled: true,
            ),
            dependencies: dependencies(date: date),
        )
        return try encode(api, ChatRequestBody(messages: messages, tools: toolDefinitions(mcpTools: mcpTools)))
    }

    func serializedTools(_ api: API, mcpTools: [MCPToolInfo]) throws -> Data {
        try encode(api, ChatRequestBody(
            messages: [.user(content: .text("hello"))],
            tools: toolDefinitions(mcpTools: mcpTools),
        ))
    }

    func encode(_ api: API, _ body: ChatRequestBody) throws -> Data {
        let request: URLRequest
        switch api {
        case .completions:
            let client = RemoteCompletionsChatClient(
                model: "test-model",
                baseURL: "https://example.com",
                path: "/v1/chat/completions",
                apiKey: "test-key",
            )
            request = try client.makeURLRequest(body: client.resolve(body: body, stream: true))
        case .responses:
            let client = RemoteResponsesChatClient(
                model: "test-model",
                baseURL: "https://example.com",
                path: "/v1/responses",
                apiKey: "test-key",
            )
            request = try client.makeURLRequest(body: client.resolve(body: body, stream: true))
        }
        return try #require(request.httpBody)
    }

    func jsonObject(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func commonPrefixLength(_ lhs: Data, _ rhs: Data) -> Int {
        zip(lhs, rhs).prefix { $0 == $1 }.count
    }

    func commonSuffixLength(_ lhs: Data, _ rhs: Data) -> Int {
        zip(lhs.reversed(), rhs.reversed()).prefix { $0 == $1 }.count
    }
}

private extension ChatRequestBody.Tool {
    var functionName: String? {
        switch self {
        case let .function(name, _, _, _): name
        }
    }
}

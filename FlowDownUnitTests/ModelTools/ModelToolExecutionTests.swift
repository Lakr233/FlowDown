//
//  ModelToolExecutionTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@testable import FlowDown
import Combine
import Foundation
import Testing

private final class StubTool: ModelTool, @unchecked Sendable {
    let name: String
    let parameters: [String: AnyCodingValue]
    let access: ModelToolAccess

    init(
        name: String = "stub_tool",
        parameters: [String: AnyCodingValue] = [
            "type": "object",
            "properties": ["query": ["type": "string"]],
            "required": ["query"],
            "additionalProperties": false,
        ],
        access: ModelToolAccess = .general,
    ) {
        self.name = name
        self.parameters = parameters
        self.access = access
    }

    var definition: ChatRequestBody.Tool {
        .function(name: name, description: "Stub", parameters: parameters, strict: true)
    }

    var interfaceName: String {
        name
    }

    var interfaceIcon: String {
        "hammer"
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        ModelToolOutput(text: arguments.json)
    }
}

@Suite(.serialized)
struct ModelToolExecutionTests {
    @Test
    func `reason is added to every offered definition as a required string`() throws {
        let toolSet = ModelToolSet(tools: [StubTool()])
        let definition = try #require(toolSet.definitions?.first)
        guard case let .function(_, _, parameters, strict) = definition,
              case let .object(properties)? = parameters?["properties"],
              case let .array(required)? = parameters?["required"]
        else {
            Issue.record("expected an object schema")
            return
        }
        #expect(strict == true)
        #expect(properties[ModelToolReason.key] != nil)
        #expect(properties["query"] != nil)
        #expect(required == [.string("query"), .string(ModelToolReason.key)])
    }

    @Test
    func `a tool that declares its own reason keeps it on the arguments`() throws {
        let tool = StubTool(parameters: [
            "type": "object",
            "properties": ["reason": ["type": "string"]],
            "required": ["reason"],
            "additionalProperties": false,
        ])
        let toolSet = ModelToolSet(tools: [tool])
        let call = try #require(toolSet.resolve(ToolRequest(name: "stub_tool", args: #"{"reason":"cleanup"}"#)))
        #expect(call.reason == nil)
        #expect(call.arguments.string("reason") == "cleanup")
    }

    @Test
    func `resolving a call takes the reason off the arguments`() throws {
        let toolSet = ModelToolSet(tools: [StubTool()])
        let call = try #require(toolSet.resolve(ToolRequest(
            name: "stub_tool",
            args: #"{"query":"weather","reason":"  Check the forecast  "}"#,
        )))
        #expect(call.reason == "Check the forecast")
        #expect(call.arguments.string("reason") == nil)
        #expect(call.arguments.string("query") == "weather")
    }

    @Test
    func `calls resolve against the offered tools only, preferring an exact name`() {
        let toolSet = ModelToolSet(tools: [StubTool(name: "Lookup"), StubTool(name: "lookup")])
        #expect(toolSet.resolve(ToolRequest(name: "lookup", args: "{}"))?.tool.functionName == "lookup")
        #expect(toolSet.resolve(ToolRequest(name: "LOOKUP", args: "{}")) != nil)
        #expect(toolSet.resolve(ToolRequest(name: "missing", args: "{}")) == nil)
        #expect(ModelToolSet.empty.definitions == nil)
    }

    @Test
    func `arguments that are not an object pass through untouched`() {
        let split = ModelToolReason.split("not json")
        #expect(split.arguments == "not json")
        #expect(split.reason == nil)
    }

    @Test
    func `only private data and external tools need approval, and only while required`() {
        let saved = ModelToolAuthorization.requiresConfirmation
        defer { ModelToolAuthorization.requiresConfirmation = saved }

        ModelToolAuthorization.requiresConfirmation = true
        #expect(!ModelToolAuthorization.needsApproval(StubTool(access: .general)))
        #expect(ModelToolAuthorization.needsApproval(StubTool(access: .privateData)))
        #expect(ModelToolAuthorization.needsApproval(StubTool(access: .external)))

        ModelToolAuthorization.requiresConfirmation = false
        #expect(!ModelToolAuthorization.needsApproval(StubTool(access: .privateData)))
        #expect(!ModelToolAuthorization.needsApproval(StubTool(access: .external)))
    }

    @Test
    func `built-in tools that reach private data ask, web and memory tools do not`() {
        #expect(MTWebSearchTool().access == .general)
        #expect(MTWebScraperTool().access == .general)
        #expect(MTStoreMemoryTool().access == .general)
        #expect(MTAddCalendarTool().access == .privateData)
        #expect(MTQueryReminderTool().access == .privateData)
    }

    @Test
    func `the legacy skip setting turns confirmation off once`() throws {
        let suiteName = "ModelToolExecutionTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let saved = ModelToolAuthorization.requiresConfirmation
        defer { ModelToolAuthorization.requiresConfirmation = saved }

        ModelToolAuthorization.requiresConfirmation = true
        defaults.set(true, forKey: ModelToolAuthorization.legacySkipConfirmationKey)
        ModelToolAuthorization.migrateLegacySetting(defaults)
        #expect(!ModelToolAuthorization.requiresConfirmation)
        #expect(defaults.object(forKey: ModelToolAuthorization.legacySkipConfirmationKey) == nil)
    }

    @Test
    func `an approval resolves the waiting call`() async {
        let gate = ModelToolApprovalGate()
        let request = Self.approvalRequest()
        let waiting = Task { await gate.request(request) }
        await Self.waitUntilPending(gate, request)
        gate.resolve(request.id, with: .approve)
        #expect(await waiting.value == .approve)
    }

    @Test
    func `a cancelled call is denied`() async {
        let gate = ModelToolApprovalGate()
        let request = Self.approvalRequest()
        let waiting = Task { await gate.request(request) }
        await Self.waitUntilPending(gate, request)
        waiting.cancel()
        #expect(await waiting.value == .deny)
    }

    @Test
    func `a stale decision is ignored`() async {
        let gate = ModelToolApprovalGate()
        let request = Self.approvalRequest()
        let waiting = Task { await gate.request(request) }
        await Self.waitUntilPending(gate, request)
        gate.resolve(UUID(), with: .approve)
        gate.resolve(request.id, with: .deny)
        #expect(await waiting.value == .deny)
    }

    private static func approvalRequest() -> ModelToolApprovalRequest {
        .init(
            id: UUID(),
            toolName: "Stub",
            icon: "hammer",
            source: nil,
            reason: "Testing",
            summary: nil,
            arguments: "{}",
        )
    }

    /// The request is published on the main queue once the call waits.
    private static func waitUntilPending(_ gate: ModelToolApprovalGate, _ request: ModelToolApprovalRequest) async {
        for _ in 0 ..< 200 {
            if await MainActor.run(body: { gate.pendingRequest.value }) == request { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("the request never became pending")
    }
}

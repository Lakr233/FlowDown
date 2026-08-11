@testable import FlowDown
import Foundation
import MCP
import os
import Storage
import Testing

@Suite(.serialized)
struct MCPServiceConnectionTests {
    @Test
    func `testConnection uses injected connection factory`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory

        let server = service.create { server in
            server.update(\.name, to: "Unit MCP")
            server.update(\.endpoint, to: "https://example.com/mcp")
            server.update(\.isEnabled, to: false)
        }

        let connection = MCPConnectionSpy(toolNames: ["search", "fetch"])
        service.connectionFactory = { _ in connection }

        defer {
            service.connectionFactory = originalFactory
            service.remove(server.id)
        }

        let summary = try await withCheckedThrowingContinuation { continuation in
            service.testConnection(serverID: server.id) { result in
                continuation.resume(with: result)
            }
        }

        #expect(summary == "Unit MCP: search, Unit MCP: fetch")
        #expect(connection.connectCount == 1)
    }

    @Test
    func `prepareForConversation connects enabled servers that never connected, sharing one flight`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory
        let connection = MCPConnectionSpy(toolNames: ["ping"])

        service.connectionFactory = { server in
            server.endpoint == "https://prepare.example.com/mcp" ? connection : originalFactory(server)
        }
        let server = service.create { server in
            server.update(\.name, to: "Prepare MCP")
            server.update(\.endpoint, to: "https://prepare.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        defer {
            service.connectionFactory = originalFactory
            service.remove(server.id)
        }

        await service.prepareForConversation()

        let committed = await MainActor.run { service.connections[server.id] != nil }
        #expect(committed)
        // Background sync raced prepare on the same server; single-flight
        // means exactly one connect happened.
        #expect(connection.connectCount == 1)
    }

    @Test
    func `hung server is abandoned after the wait timeout without blocking prepare`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory
        let originalTimeout = MCPService.conversationWaitTimeout
        MCPService.conversationWaitTimeout = .milliseconds(200)

        let hungConnection = GatedConnectionSpy()

        service.connectionFactory = { server in
            server.endpoint == "https://hung.example.com/mcp" ? hungConnection : originalFactory(server)
        }
        let server = service.create { server in
            server.update(\.name, to: "Hung MCP")
            server.update(\.endpoint, to: "https://hung.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        defer {
            MCPService.conversationWaitTimeout = originalTimeout
            service.connectionFactory = originalFactory
            service.remove(server.id)
            hungConnection.open()
        }

        let clock = ContinuousClock()
        let start = clock.now
        let errors = await service.prepareForConversation()

        #expect(clock.now - start < .seconds(10))
        #expect(errors.contains { $0 is AwaitCancellableError })
        let committed = await MainActor.run { service.connections[server.id] != nil }
        #expect(!committed)
    }

    @Test
    func `late connection commit is dropped once the server is disabled`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory
        let gatedConnection = GatedConnectionSpy()

        service.connectionFactory = { server in
            server.endpoint == "https://late.example.com/mcp" ? gatedConnection : originalFactory(server)
        }
        let server = service.create { server in
            server.update(\.name, to: "Late MCP")
            server.update(\.endpoint, to: "https://late.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        defer {
            service.connectionFactory = originalFactory
            service.remove(server.id)
        }

        // Background sync starts the flight; wait until it is inside connect.
        #expect(await eventually { gatedConnection.connectStarted })

        service.edit(identifier: server.id) {
            $0.update(\.isEnabled, to: false)
        }
        // The disable must reach syncServerConnections before the flight is
        // allowed to finish connecting.
        #expect(await eventually {
            await MainActor.run { service.connections[server.id] == nil }
        })

        gatedConnection.open()

        // The late commit has to be rejected and the connection torn down.
        #expect(await eventually { gatedConnection.disconnectCount >= 1 })
        let committed = await MainActor.run { service.connections[server.id] != nil }
        #expect(!committed)
    }
}

private func eventually(
    deadline: Duration = .seconds(10),
    _ condition: @escaping () async -> Bool,
) async -> Bool {
    let clock = ContinuousClock()
    let start = clock.now
    while clock.now - start < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

private final class MCPConnectionSpy: MCPConnectionControlling, @unchecked Sendable {
    private let connectCountLock = OSAllocatedUnfairLock(initialState: 0)
    var connectCount: Int { connectCountLock.withLock { $0 } }
    private let toolNames: [String]

    init(toolNames: [String]) {
        self.toolNames = toolNames
    }

    var hasClient: Bool {
        true
    }

    var isConnected: Bool {
        true
    }

    func connect() async throws {
        connectCountLock.withLock { $0 += 1 }
    }

    func disconnect() {}

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        toolNames.map { toolName in
            MCPToolInfo(
                name: toolName,
                serverID: serverID,
                serverName: serverName,
            )
        }
    }

    func callTool(name _: String, arguments _: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?) {
        ([], nil)
    }
}

/// A connection whose `connect()` blocks until `open()` is called, for tests
/// that need a hung or late-finishing connection attempt.
private final class GatedConnectionSpy: MCPConnectionControlling, @unchecked Sendable {
    private let gate = CancellableWaiter<Void>()
    private let state = OSAllocatedUnfairLock(initialState: (started: false, connected: false, disconnects: 0))

    var connectStarted: Bool { state.withLock { $0.started } }
    var disconnectCount: Int { state.withLock { $0.disconnects } }

    var hasClient: Bool { state.withLock { $0.connected } }
    var isConnected: Bool { state.withLock { $0.connected } }

    func open() {
        gate.complete(with: .success(()))
    }

    func connect() async throws {
        state.withLock { $0.started = true }
        try await gate.value()
        state.withLock { $0.connected = true }
    }

    func disconnect() {
        state.withLock {
            $0.connected = false
            $0.disconnects += 1
        }
    }

    func listToolInfos(serverID _: ModelContextServer.ID, serverName _: String) async throws -> [MCPToolInfo] {
        []
    }

    func callTool(name _: String, arguments _: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?) {
        ([], nil)
    }
}

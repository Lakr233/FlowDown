@testable import FlowDown
import Foundation
import MCP
import os
import Storage
import Testing

@Suite(.serialized)
struct MCPServiceSessionRecoveryTests {
    @Test
    func callToolSessionExpired_replacesDeadConnection() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let dead = SessionConnectionSpy(
            callToolError: MCP.MCPError.internalError("Session expired"),
            pingError: MCP.MCPError.internalError("Bad request"),
        )
        let fresh = SessionConnectionSpy()
        let fixture = SessionRecoveryFixture(
            endpoint: "https://expired-session.example.com/mcp",
            connections: [dead, fresh],
        )
        let service = fixture.service
        let serverID = fixture.server.id
        defer { fixture.tearDown() }

        await service.prepareForConversation()
        #expect(await fixture.registered(dead))
        #expect(dead.connectCount == 1)

        await #expect(throws: (any Error).self) {
            _ = try await service.callTool(name: "lookup", from: serverID)
        }

        // The dead session was probed and replaced by a new one; the
        // replacement's commit closed the dead session.
        #expect(dead.pingCount == 1)
        #expect(await eventually { await fixture.registered(fresh) })
        #expect(fresh.connectCount == 1)
        #expect(dead.disconnectCount == 1)
        #expect(await eventually { fixture.status == .connected })
    }

    @Test
    func callToolSessionLostAndReconnectFails_keepsDeadConnectionAndTools() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let dead = SessionConnectionSpy(
            callToolError: MCP.MCPError.internalError("Bad request"),
            pingError: MCP.MCPError.internalError("Bad request"),
        )
        let unreachable = SessionConnectionSpy(connectError: URLError(.cannotConnectToHost))
        let fixture = SessionRecoveryFixture(
            endpoint: "https://reconnect-failure.example.com/mcp",
            connections: [dead, unreachable],
        )
        let service = fixture.service
        let serverID = fixture.server.id
        defer { fixture.tearDown() }

        await service.prepareForConversation()
        #expect(await fixture.registered(dead))

        await #expect(throws: (any Error).self) {
            _ = try await service.callTool(name: "lookup", from: serverID)
        }

        // The reconnect was attempted and failed.
        #expect(await eventually { unreachable.connectCount == 1 })
        #expect(await eventually { fixture.status == .disconnected })

        // The dead connection and its tools stay, so the model's tool list
        // still resolves and the next call fails as an ordinary tool error.
        #expect(await fixture.registered(dead))
        #expect(dead.disconnectCount == 0)
        let tools = await service.getAllTools()
        #expect(tools.contains { $0.serverID == serverID && $0.name == "lookup" })
    }

    @Test
    func callToolPingTimesOut_keepsConnectionWithoutReconnecting() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        // A ping that times out is inconclusive; the spy reports the timeout
        // directly so the shared wait timeout stays untouched.
        let silent = SessionConnectionSpy(
            callToolError: URLError(.timedOut),
            pingError: AwaitCancellableError.timedOut,
        )
        let fixture = SessionRecoveryFixture(
            endpoint: "https://silent-session.example.com/mcp",
            connections: [silent],
        )
        let service = fixture.service
        let serverID = fixture.server.id
        defer { fixture.tearDown() }

        await service.prepareForConversation()
        #expect(await fixture.registered(silent))

        await #expect(throws: (any Error).self) {
            _ = try await service.callTool(name: "lookup", from: serverID)
        }

        // A reconnect would have moved the status to connecting at once.
        #expect(silent.pingCount == 1)
        #expect(fixture.status == .connected)
        #expect(fixture.factoryCallCount == 1)
        #expect(await fixture.registered(silent))
        #expect(silent.disconnectCount == 0)
    }

    @Test
    func callToolErrorWithLiveSession_keepsConnectionAndTools() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let connection = SessionConnectionSpy(
            callToolError: MCP.MCPError.invalidParams("missing query"),
        )
        let fixture = SessionRecoveryFixture(
            endpoint: "https://live-session.example.com/mcp",
            connections: [connection],
        )
        let service = fixture.service
        let serverID = fixture.server.id
        defer { fixture.tearDown() }

        await service.prepareForConversation()
        #expect(await MainActor.run { service.cachedToolInfos(for: serverID) != nil })

        await #expect(throws: (any Error).self) {
            _ = try await service.callTool(name: "lookup", from: serverID)
        }

        #expect(connection.pingCount == 1)
        #expect(connection.disconnectCount == 0)
        #expect(connection.connectCount == 1)
        #expect(fixture.factoryCallCount == 1)
        let kept = await MainActor.run {
            service.connections[serverID] != nil && service.cachedToolInfos(for: serverID) != nil
        }
        #expect(kept)
    }
}

/// An enabled server on the shared service whose connection factory hands
/// out `connections` in order, repeating the last one.
private final class SessionRecoveryFixture: @unchecked Sendable {
    let service: MCPService
    let server: ModelContextServer
    private let originalFactory: MCPService.ConnectionFactory
    private let factoryCalls: OSAllocatedUnfairLock<Int>

    init(endpoint: String, connections: [SessionConnectionSpy]) {
        precondition(!connections.isEmpty)
        let service = MCPService.shared
        let originalFactory = service.connectionFactory
        let factoryCalls = OSAllocatedUnfairLock(initialState: 0)
        self.service = service
        self.originalFactory = originalFactory
        self.factoryCalls = factoryCalls
        service.connectionFactory = { server in
            guard server.endpoint == endpoint else { return originalFactory(server) }
            let index = factoryCalls.withLock { calls in
                calls += 1
                return calls - 1
            }
            return connections[min(index, connections.count - 1)]
        }
        server = service.create { server in
            server.update(\.name, to: "Session Recovery MCP")
            server.update(\.endpoint, to: endpoint)
            server.update(\.isEnabled, to: true)
        }
    }

    var factoryCallCount: Int { factoryCalls.withLock { $0 } }

    var status: ModelContextServer.ConnectionStatus? {
        service.server(with: server.id)?.connectionStatus
    }

    func registered(_ connection: SessionConnectionSpy) async -> Bool {
        let serverID = server.id
        let service = service
        return await MainActor.run {
            guard let current = service.connections[serverID] else { return false }
            return current === connection
        }
    }

    func tearDown() {
        service.connectionFactory = originalFactory
        service.remove(server.id)
    }
}

private final class SessionConnectionSpy: MCPConnectionControlling, @unchecked Sendable {
    private let callToolError: Error?
    private let pingError: Error?
    private let connectError: Error?
    private let state = OSAllocatedUnfairLock(
        initialState: (connected: false, connects: 0, disconnects: 0, pings: 0),
    )

    init(callToolError: Error? = nil, pingError: Error? = nil, connectError: Error? = nil) {
        self.callToolError = callToolError
        self.pingError = pingError
        self.connectError = connectError
    }

    var connectCount: Int { state.withLock { $0.connects } }
    var disconnectCount: Int { state.withLock { $0.disconnects } }
    var pingCount: Int { state.withLock { $0.pings } }

    var isConnected: Bool { state.withLock { $0.connected } }

    func connect() async throws {
        let connectError = connectError
        state.withLock {
            $0.connects += 1
            if connectError == nil { $0.connected = true }
        }
        if let connectError { throw connectError }
    }

    func disconnect() {
        state.withLock {
            $0.connected = false
            $0.disconnects += 1
        }
    }

    func ping() async throws {
        state.withLock { $0.pings += 1 }
        if let pingError { throw pingError }
    }

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        [MCPToolInfo(name: "lookup", serverID: serverID, serverName: serverName)]
    }

    func callTool(
        name _: String,
        arguments _: [String: Value]?
    ) async throws -> (content: [Tool.Content], isError: Bool?) {
        if let callToolError { throw callToolError }
        return ([], nil)
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

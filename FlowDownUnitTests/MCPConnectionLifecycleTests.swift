@testable import FlowDown
import Foundation
import MCP
import os
import Storage
import Testing

@Suite(.serialized)
struct MCPConnectionLifecycleTests {
    @Test(.timeLimit(.minutes(1)))
    func connectInitializeRejected_disconnectsTransport() async throws {
        let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
        try await serverTransport.connect()

        // A server that answers every request, initialize included, with an
        // error, and notes when the client side of the pair goes away.
        let peer = PeerProbe()
        let serverMessages = await serverTransport.receive()
        let server = Task {
            do {
                for try await data in serverMessages {
                    guard let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          let id = request["id"]
                    else { continue }
                    let reply: [String: Any] = [
                        "jsonrpc": "2.0",
                        "id": id,
                        "error": ["code": -32603, "message": "initialize rejected"] as [String: Any],
                    ]
                    try await serverTransport.send(JSONSerialization.data(withJSONObject: reply))
                }
            } catch {}
            peer.markClosed()
        }
        defer { server.cancel() }

        let connection = MCPConnection(
            config: ModelContextServer(name: "Rejecting MCP", endpoint: "https://rejecting.example.com/mcp"),
            transportFactory: { _ in clientTransport },
        )

        await #expect(throws: (any Error).self) {
            try await connection.connect()
        }
        #expect(!connection.isConnected)
        // The client's transport was disconnected instead of being left
        // running behind a dropped client.
        #expect(await eventually { peer.closed })
    }

    @Test
    func testConnectionToolListingFails_disconnectsConnection() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory
        let endpoint = "https://listing-failure.example.com/mcp"

        let server = service.create { server in
            server.update(\.name, to: "Listing Failure MCP")
            server.update(\.endpoint, to: endpoint)
            server.update(\.isEnabled, to: false)
        }
        let connection = ListingFailureConnectionSpy()
        service.connectionFactory = { server in
            server.endpoint == endpoint ? connection : originalFactory(server)
        }
        defer {
            service.connectionFactory = originalFactory
            service.remove(server.id)
        }

        let result: Result<String, Error> = await withCheckedContinuation { continuation in
            service.testConnection(serverID: server.id) { result in
                continuation.resume(returning: result)
            }
        }

        if case .success = result {
            Issue.record("Expected the connection test to fail when listing tools fails.")
        }
        #expect(connection.connectCount == 1)
        #expect(connection.disconnectCount == 1)
        let committed = await MainActor.run { service.connections[server.id] != nil }
        #expect(!committed)
    }
}

private final class PeerProbe: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: false)

    var closed: Bool { state.withLock { $0 } }

    func markClosed() {
        state.withLock { $0 = true }
    }
}

private final class ListingFailureConnectionSpy: MCPConnectionControlling, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (connects: 0, disconnects: 0))

    var connectCount: Int { state.withLock { $0.connects } }
    var disconnectCount: Int { state.withLock { $0.disconnects } }

    var isConnected: Bool {
        true
    }

    func connect() async throws {
        state.withLock { $0.connects += 1 }
    }

    func disconnect() {
        state.withLock { $0.disconnects += 1 }
    }

    func listToolInfos(serverID _: ModelContextServer.ID, serverName _: String) async throws -> [MCPToolInfo] {
        throw FlowDown.MCPError.connectionFailed
    }

    func callTool(
        name _: String,
        arguments _: [String: Value]?
    ) async throws -> (content: [Tool.Content], isError: Bool?) {
        ([], nil)
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

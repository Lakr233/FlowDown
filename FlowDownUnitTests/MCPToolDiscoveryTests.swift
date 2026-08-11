@testable import FlowDown
import Foundation
import MCP
import Storage
import Testing

@Suite(.serialized)
struct MCPToolDiscoveryTests {
    @Test
    func `getAllTools maps hosts and ignores disabled or failing servers`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory

        let hostServer = service.create { server in
            server.update(\.name, to: "Host Server")
            server.update(\.endpoint, to: "https://alpha.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        let fallbackServer = service.create { server in
            server.update(\.name, to: "Fallback Server")
            server.update(\.endpoint, to: "not-a-valid-url")
            server.update(\.isEnabled, to: true)
        }
        let failingServer = service.create { server in
            server.update(\.name, to: "Failing Server")
            server.update(\.endpoint, to: "https://beta.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        let disabledServer = service.create { server in
            server.update(\.name, to: "Disabled Server")
            server.update(\.endpoint, to: "https://disabled.example.com/mcp")
            server.update(\.isEnabled, to: false)
        }

        let hostConnection = DiscoveryConnectionSpy(toolNames: ["search"])
        let fallbackConnection = DiscoveryConnectionSpy(toolNames: ["echo"])
        let failingConnection = DiscoveryConnectionSpy(toolNames: ["broken"], listToolError: FlowDown.MCPError.connectionFailed)
        let disabledConnection = DiscoveryConnectionSpy(toolNames: ["hidden"])
        let connections: [ModelContextServer.ID: DiscoveryConnectionSpy] = [
            hostServer.id: hostConnection,
            fallbackServer.id: fallbackConnection,
            failingServer.id: failingConnection,
            disabledServer.id: disabledConnection,
        ]

        service.connectionFactory = { server in
            connections[server.id] ?? originalFactory(server)
        }

        defer {
            service.connectionFactory = originalFactory
            service.remove(hostServer.id)
            service.remove(fallbackServer.id)
            service.remove(failingServer.id)
            service.remove(disabledServer.id)
        }

        _ = try await testConnection(service: service, serverID: hostServer.id)
        _ = try await testConnection(service: service, serverID: fallbackServer.id)

        do {
            _ = try await testConnection(service: service, serverID: failingServer.id)
            Issue.record("Expected failing MCP server to report an error.")
        } catch {}

        _ = try await testConnection(service: service, serverID: disabledServer.id)

        let tools = await service.getAllTools()

        #expect(tools.contains { tool in
            tool.serverID == hostServer.id
                && tool.serverName == "alpha.example.com"
                && tool.name == "search"
        })
        #expect(tools.contains { tool in
            tool.serverID == fallbackServer.id
                && tool.serverName == fallbackServer.id
                && tool.name == "echo"
        })
        #expect(!tools.contains { $0.serverID == failingServer.id })
        #expect(!tools.contains { $0.serverID == disabledServer.id })
    }

    @Test
    func `listServerTools wraps discovered tools and callTool requires a connection`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let service = MCPService.shared
        let originalFactory = service.connectionFactory

        let connectedServer = service.create { server in
            server.update(\.name, to: "Connected Server")
            server.update(\.endpoint, to: "https://tools.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }
        let unconnectedServer = service.create { server in
            server.update(\.name, to: "Unconnected Server")
            server.update(\.endpoint, to: "https://offline.example.com/mcp")
            server.update(\.isEnabled, to: true)
        }

        let connectedConnection = DiscoveryConnectionSpy(
            toolNames: ["translate"],
            toolDescriptions: ["translate": "translate text"],
        )
        service.connectionFactory = { server in
            if server.id == connectedServer.id {
                return connectedConnection
            }
            return originalFactory(server)
        }

        defer {
            service.connectionFactory = originalFactory
            service.remove(connectedServer.id)
            service.remove(unconnectedServer.id)
        }

        _ = try await testConnection(service: service, serverID: connectedServer.id)

        let tools = await service.listServerTools()
        let tool = try #require(
            tools.first(where: {
                $0.toolInfo.serverID == connectedServer.id && $0.toolInfo.name == "translate"
            }),
        )

        #expect(tool.functionName == "translate")
        #expect(tool.toolInfo.description == "translate text")

        do {
            _ = try await service.callTool(name: "translate", from: unconnectedServer.id)
            Issue.record("Expected callTool to fail when no connection exists.")
        } catch let error as FlowDown.MCPError {
            #expect(error == .connectionFailed)
        } catch {
            Issue.record("Expected MCPError.connectionFailed, got \(error).")
        }
    }
}

private extension MCPToolDiscoveryTests {
    func testConnection(
        service: MCPService,
        serverID: ModelContextServer.ID,
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.testConnection(serverID: serverID) { result in
                continuation.resume(with: result)
            }
        }
    }
}

private final class DiscoveryConnectionSpy: MCPConnectionControlling, @unchecked Sendable {
    private let toolNames: [String]
    private let toolDescriptions: [String: String]
    private let listToolError: Error?

    init(
        toolNames: [String],
        toolDescriptions: [String: String] = [:],
        listToolError: Error? = nil,
    ) {
        self.toolNames = toolNames
        self.toolDescriptions = toolDescriptions
        self.listToolError = listToolError
    }

    var hasClient: Bool {
        true
    }

    var isConnected: Bool {
        true
    }

    func connect() async throws {}

    func disconnect() {}

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        if let listToolError {
            throw listToolError
        }

        return toolNames.map { toolName in
            MCPToolInfo(
                name: toolName,
                description: toolDescriptions[toolName],
                serverID: serverID,
                serverName: serverName,
            )
        }
    }

    func callTool(name _: String, arguments _: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?) {
        ([], nil)
    }
}

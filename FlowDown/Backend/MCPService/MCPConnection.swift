//
//  MCPConnection.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Combine
import Foundation
import MCP
import os
import Storage

// MARK: - Connection Manager

protocol MCPConnectionControlling: AnyObject, Sendable {
    var hasClient: Bool { get }
    var isConnected: Bool { get }

    func connect() async throws
    func disconnect()
    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo]
    func callTool(name: String, arguments: [String: Value]?) async throws -> (content: [Tool.Content], isError: Bool?)
}

final class MCPConnection: MCPConnectionControlling, @unchecked Sendable {
    // MARK: - Properties

    private let config: ModelContextServer
    // Guards the only mutable state; an MCP.Client taken out of the lock is an
    // actor, so calls on it are safe from any concurrency domain.
    private let clientLock = OSAllocatedUnfairLock<MCP.Client?>(initialState: nil)

    var client: MCP.Client? {
        clientLock.withLock { $0 }
    }

    // MARK: - Initialization

    init(config: ModelContextServer) {
        self.config = config
    }

    // MARK: - Connection Management

    func connect() async throws {
        guard client == nil else {
            Logger.network.infoFile("client already connected for \(config.id)")
            return
        }

        let client = createClient()
        let transport = try config.createTransport()

        Logger.network.infoFile("connecting client for server: \(config.id)")
        try await client.connect(transport: transport)

        let raced: MCP.Client? = clientLock.withLock { current in
            if current == nil {
                current = client
                return nil
            }
            return client
        }
        if let raced {
            // Another connect won while we were awaiting; drop ours.
            Task.detached { await raced.disconnect() }
            return
        }
        Logger.network.infoFile("successfully connected to server: \(config.id)")
    }

    func disconnect() {
        let client = clientLock.withLock { current -> MCP.Client? in
            defer { current = nil }
            return current
        }
        guard let client else { return }

        Logger.network.infoFile("disconnecting client for server: \(config.id)")
        Task.detached { await client.disconnect() }
        Logger.network.infoFile("client disconnected for server: \(config.id)")
    }

    var isConnected: Bool {
        client != nil
    }

    var hasClient: Bool {
        client != nil
    }

    func listToolInfos(serverID: ModelContextServer.ID, serverName: String) async throws -> [MCPToolInfo] {
        guard let client else {
            throw MCPError.connectionFailed
        }

        let tools = try await client.listTools().tools
        return tools.map { tool in
            MCPToolInfo(
                tool: tool,
                serverID: serverID,
                serverName: serverName,
            )
        }
    }

    func callTool(name: String, arguments: [String: Value]? = nil) async throws -> (content: [Tool.Content], isError: Bool?) {
        guard let client else {
            throw MCPError.connectionFailed
        }

        // The RequestContext overload (explicit annotation selects it over the
        // async tuple one) lets us stop waiting the moment the user cancels:
        // our own continuation returns immediately, while cancelRequest tells
        // the server and cleans up the SDK side on a best-effort basis. The
        // SDK's plain callTool awaits an unstructured task that no amount of
        // cooperative cancellation can interrupt.
        let context: RequestContext<CallTool.Result> = try await client.callTool(name: name, arguments: arguments)
        let result = try await awaitCancellable {
            try await context.value
        } onAbandon: {
            Task { try? await client.cancelRequest(context.requestID, reason: "User cancelled") }
        }
        return (content: result.content, isError: result.isError)
    }

    private func createClient() -> MCP.Client {
        let bundleId = Bundle.main.bundleIdentifier ?? "flowdown.ai"
        return MCP.Client(name: bundleId, version: AnchorVersion.version)
    }
}

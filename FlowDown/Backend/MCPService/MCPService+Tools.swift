//
//  MCPService+Tools.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation
import MCP
import Storage

// MARK: - MCPService Tools Extension

extension MCPService {
    func callTool(
        name: String,
        arguments: [String: Value]? = nil,
        from clientName: String
    ) async throws -> (content: [Tool.Content], isError: Bool?) {
        let connection = await MainActor.run { connections[clientName] }
        guard let connection, connection.isConnected else {
            throw MCPError.connectionFailed
        }

        do {
            return try await connection.callTool(name: name, arguments: arguments)
        } catch {
            // This call still fails. A short wait for the replacement lets
            // the next call in the same turn reach the new session; a slow
            // or failed reconnect leaves the dead one registered, so that
            // call fails as an ordinary tool error instead.
            if let reconnect = await replaceConnectionIfSessionLost(connection, for: clientName, after: error) {
                _ = try? await awaitCancellable(timeout: Self.conversationWaitTimeout) {
                    await reconnect.value
                }
            }
            throw error
        }
    }

    func getAllTools() async -> [MCPToolInfo] {
        let snapshot: [(id: ModelContextServer.ID, connection: any MCPConnectionControlling)] = await MainActor.run {
            connections.compactMap { serverID, connection in
                guard let server = server(with: serverID),
                      server.isEnabled,
                      connection.isConnected
                else { return nil }
                return (serverID, connection)
            }
        }

        var allTools: [MCPToolInfo] = []
        for (serverID, connection) in snapshot {
            if let cached = await MainActor.run(body: { cachedToolInfos(for: serverID) }) {
                allTools.append(contentsOf: cached)
                continue
            }
            guard let server = server(with: serverID) else { continue }
            do {
                // Bounded wait: a hung server loses its tools for this round
                // instead of hanging the whole conversation setup.
                let toolInfos = try await awaitCancellable(timeout: Self.conversationWaitTimeout) {
                    try await connection.listToolInfos(
                        serverID: serverID,
                        serverName: Self.toolListingName(for: server),
                    )
                }
                await MainActor.run { storeToolInfos(toolInfos, for: serverID) }
                allTools.append(contentsOf: toolInfos)
            } catch {
                Logger.network.errorFile("failed to acquire tools from \(serverID): \(error.localizedDescription)")
                await replaceConnectionIfSessionLost(connection, for: serverID, after: error)
            }
        }

        return Self.sortedForListing(allTools)
    }

    /// Orders tools by server (listing name, then id) and then tool name.
    /// Connections live in a dictionary whose iteration order changes between
    /// launches, and the tool list is part of the prompt prefix providers
    /// cache, so it must not depend on that order. The original position
    /// breaks remaining ties so duplicate names keep the server's order.
    static func sortedForListing(_ tools: [MCPToolInfo]) -> [MCPToolInfo] {
        tools.enumerated().sorted { lhs, rhs in
            let lhsKey = (lhs.element.serverName, lhs.element.serverID, lhs.element.name)
            let rhsKey = (rhs.element.serverName, rhs.element.serverID, rhs.element.name)
            if lhsKey != rhsKey { return lhsKey < rhsKey }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}

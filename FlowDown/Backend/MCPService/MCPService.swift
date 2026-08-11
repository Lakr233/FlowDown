//
//  MCPService.swift
//  FlowDown
//
//  Created by LiBr on 6/29/25.
//

import Combine
import Foundation
import MCP
import Storage

class MCPService: NSObject {
    static let shared = MCPService()
    typealias ConnectionFactory = (ModelContextServer) -> any MCPConnectionControlling

    // MARK: - Properties

    let servers: CurrentValueSubject<[ModelContextServer], Never> = .init([])
    private var cancellables = Set<AnyCancellable>()
    var connectionFactory: ConnectionFactory = { MCPConnection(config: $0) }

    /// How long conversation setup waits for a single server before giving up
    /// on it. The underlying connect/listTools calls do not honor cooperative
    /// cancellation, so the wait is abandoned rather than the work cancelled.
    /// Mutable so tests can shrink it; production code never writes it.
    static var conversationWaitTimeout: Duration = .seconds(15)

    // MARK: - Connection State (MainActor-owned)

    // Every mutation of the connection dictionaries happens on the main actor:
    // it is the single owner that serializes background sync, conversation
    // prepare, connection tests and UI edits. Network waits never run on it —
    // only the bookkeeping around them.
    @MainActor private(set) var connections: [ModelContextServer.ID: any MCPConnectionControlling] = [:]
    @MainActor private var connectionFlights: [ModelContextServer.ID: ConnectionFlight] = [:]
    @MainActor private var connectionGeneration: [ModelContextServer.ID: Int] = [:]
    @MainActor private var toolInfoCache: [ModelContextServer.ID: [MCPToolInfo]] = [:]

    @MainActor
    private struct ConnectionFlight {
        let generation: Int
        let fingerprint: String
        let task: Task<(any MCPConnectionControlling)?, Never>
    }

    // MARK: - Initialization

    override private init() {
        super.init()
        for server in sdb.modelContextServerList() {
            updateServerStatus(server.id, status: .disconnected)
        }
        updateFromDatabase()
        setupServerSync()

        NotificationCenter.default.publisher(for: SyncEngine.ModelContextServerChanged)
            .debounce(for: .seconds(2), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                logger.infoFile("Recived SyncEngine.ModelContextServerChanged")
                self?.updateFromDatabase()
            }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    private func setupServerSync() {
        servers
            .map { $0.filter(\.isEnabled) }
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] enabledServers in
                guard let self else { return }
                Task { @MainActor in
                    self.syncServerConnections(enabledServers)
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods

    /// Connects every enabled server that is not connected yet — including
    /// ones that never connected before — and waits a bounded time for each.
    /// Servers that exceed the timeout keep connecting in the background and
    /// commit their connection for the next round; this call just stops
    /// waiting for them.
    @discardableResult
    func prepareForConversation(progress: (@Sendable (String) -> Void)? = nil) async -> [Swift.Error] {
        let targets = servers.value.filter(\.isEnabled)
        guard !targets.isEmpty else { return [] }
        let total = targets.count

        var errors: [Swift.Error] = []
        var done = 0
        await withTaskGroup(of: (String, Swift.Error?).self) { group in
            for server in targets {
                group.addTask { [self] in
                    let name = server.displayName
                    do {
                        let alreadyConnected = await MainActor.run {
                            self.connections[server.id]?.isConnected ?? false
                        }
                        if alreadyConnected { return (name, nil) }
                        let flight = await MainActor.run { self.connectionTask(for: server) }
                        let connection = try await awaitCancellable(timeout: Self.conversationWaitTimeout) {
                            await flight.value
                        }
                        guard connection != nil else { return (name, MCPError.connectionFailed) }
                        return (name, nil)
                    } catch {
                        return (name, error)
                    }
                }
            }
            for await (name, error) in group {
                done += 1
                if let error {
                    Logger.network.errorFile("failed to prepare server \(name): \(error.localizedDescription)")
                    errors.append(error)
                }
                progress?(String(localized: "Connecting to \(name) (\(done)/\(total))"))
            }
        }
        return errors
    }

    func insert(_ server: ModelContextServer) {
        sdb.modelContextServerPut(object: server)
        updateFromDatabase()
    }

    @MainActor
    @discardableResult
    func importServer(from data: Data) throws -> ModelContextServer {
        let server = try ModelContextServer.decodeCompatible(from: data)

        // Basic validation: endpoint is required.
        if server.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "MCPImport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid MCP server configuration: missing endpoint."],
            )
        }

        // Always treat imports as a new local object.
        server.update(\.deviceId, to: Storage.deviceId)
        server.update(\.objectId, to: UUID().uuidString)
        server.update(\.removed, to: false)

        let now = Date.now
        server.update(\.creation, to: now)
        server.update(\.modified, to: now)

        // Reset volatile connection state.
        server.update(\.lastConnected, to: nil)
        server.update(\.connectionStatus, to: .disconnected)

        insert(server)
        return server
    }

    func exportServerData(_ server: ModelContextServer) throws -> Data {
        if server.endpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw NSError(
                domain: "MCPExport",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid MCP server configuration: missing endpoint."],
            )
        }

        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(server)

        // Validate round-trip decodability (including legacy format support).
        _ = try ModelContextServer.decodeCompatible(from: data)
        return data
    }

    func ensureOrReconnect(_ serverID: ModelContextServer.ID) {
        Task { @MainActor in
            if let connection = connections[serverID], connection.hasClient { return }
            guard let server = self.server(with: serverID) else { return }
            updateServerStatus(serverID, status: .disconnected)
            _ = connectionTask(for: server)
        }
    }

    /// Tests a server by building a fresh, throwaway connection — pending or
    /// established connections are torn down first so the test is real. Works
    /// for disabled servers too; the connection is only kept when the server
    /// is enabled and its configuration did not change during the test.
    func testConnection(
        serverID: ModelContextServer.ID,
        completion: @escaping (Result<String, Swift.Error>) -> Void,
    ) {
        Task {
            do {
                guard let server = self.server(with: serverID) else {
                    throw MCPError.invalidConfiguration
                }
                let generation = await MainActor.run {
                    self.dropConnection(for: serverID)
                    self.updateServerStatus(serverID, status: .disconnected)
                    return self.connectionGeneration[serverID, default: 0]
                }
                let connection = self.connectionFactory(server)
                try await connection.connect()
                let toolInfos = try await connection.listToolInfos(
                    serverID: serverID,
                    serverName: server.displayName,
                )
                let fingerprint = Self.configFingerprint(server)
                await MainActor.run {
                    guard let current = self.server(with: serverID),
                          current.isEnabled,
                          self.connectionGeneration[serverID, default: 0] == generation,
                          Self.configFingerprint(current) == fingerprint
                    else {
                        connection.disconnect()
                        self.updateServerStatus(serverID, status: .connected)
                        return
                    }
                    self.commitConnection(connection, for: serverID)
                    self.updateServerStatus(serverID, status: .connected)
                }
                let toolSummary = toolInfos.map { toolInfo in
                    if let toolServer = self.server(with: serverID) {
                        return "\(toolServer.displayName): \(toolInfo.name)"
                    }
                    return toolInfo.name
                }.joined(separator: ", ")
                completion(.success(toolSummary))
            } catch {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Private Connection Management

    @MainActor
    private func syncServerConnections(_ eligibleServers: [ModelContextServer]) {
        for server in eligibleServers {
            ensureOrReconnect(server.id)
        }

        let eligibleServerIds = Set(eligibleServers.map(\.id))
        for serverId in Set(connections.keys).union(connectionFlights.keys) {
            if !eligibleServerIds.contains(serverId) {
                dropConnection(for: serverId)
                updateServerStatus(serverId, status: .disconnected)
            }
        }
    }

    /// The single-flight entry: at most one connection attempt runs per
    /// server. Reuses a compatible in-flight attempt; a stale one (config
    /// changed) is dropped and replaced. The attempt commits its result on
    /// the main actor only when it is still the current flight for a still
    /// enabled, unchanged server — a late connection for a server that was
    /// disabled, removed or edited in the meantime is disconnected instead.
    @MainActor
    private func connectionTask(for server: ModelContextServer) -> Task<(any MCPConnectionControlling)?, Never> {
        let serverID = server.id
        let fingerprint = Self.configFingerprint(server)

        if let existing = connectionFlights[serverID] {
            if existing.fingerprint == fingerprint {
                return existing.task
            }
            invalidateFlight(for: serverID)
        }

        let generation = connectionGeneration[serverID, default: 0]
        updateServerStatus(serverID, status: .connecting)

        let task = Task<(any MCPConnectionControlling)?, Never> { [self] in
            let connection = connectionFactory(server)
            do {
                try await connection.connect()
            } catch {
                Logger.network.errorFile("failed to connect to server \(serverID): \(error.localizedDescription)")
                await MainActor.run {
                    self.clearFlight(for: serverID, generation: generation)
                    if self.connections[serverID] == nil {
                        self.updateServerStatus(serverID, status: .disconnected)
                    }
                }
                return nil
            }

            // Tool discovery is part of bringing a server up, but a hung
            // listTools must not pin this flight forever; the cache just
            // stays empty and getAllTools retries later with its own bound.
            let discoveredTools: [MCPToolInfo]? = try? await awaitCancellable(timeout: Self.conversationWaitTimeout) {
                try await connection.listToolInfos(
                    serverID: serverID,
                    serverName: Self.toolListingName(for: server),
                )
            }

            return await MainActor.run {
                guard let current = self.server(with: serverID),
                      current.isEnabled,
                      self.connectionGeneration[serverID, default: 0] == generation,
                      Self.configFingerprint(current) == fingerprint
                else {
                    self.clearFlight(for: serverID, generation: generation)
                    connection.disconnect()
                    return nil
                }
                self.clearFlight(for: serverID, generation: generation)
                self.commitConnection(connection, for: serverID)
                if let discoveredTools {
                    self.toolInfoCache[serverID] = discoveredTools
                    self.updateCapabilities(for: serverID, hasTools: !discoveredTools.isEmpty)
                }
                self.updateServerStatus(serverID, status: .connected)
                return connection
            }
        }

        connectionFlights[serverID] = .init(generation: generation, fingerprint: fingerprint, task: task)
        return task
    }

    /// Stores the connection, disconnecting any different one already there —
    /// concurrent commits (a test racing a background flight) must never leak
    /// the replaced client.
    @MainActor
    private func commitConnection(_ connection: any MCPConnectionControlling, for serverID: ModelContextServer.ID) {
        if let existing = connections[serverID], existing !== connection {
            existing.disconnect()
        }
        connections[serverID] = connection
    }

    /// Tears down whatever exists for the server: the live connection, the
    /// in-flight attempt (its late commit will fail the generation check),
    /// and the tool cache.
    @MainActor
    func dropConnection(for serverID: ModelContextServer.ID) {
        invalidateFlight(for: serverID)
        if let connection = connections.removeValue(forKey: serverID) {
            connection.disconnect()
        }
        toolInfoCache[serverID] = nil
    }

    @MainActor
    private func invalidateFlight(for serverID: ModelContextServer.ID) {
        connectionGeneration[serverID, default: 0] += 1
        connectionFlights[serverID] = nil
    }

    /// Removes the flight record, but only when it still belongs to the
    /// caller — never a newer attempt that replaced it.
    @MainActor
    private func clearFlight(for serverID: ModelContextServer.ID, generation: Int) {
        guard connectionFlights[serverID]?.generation == generation else { return }
        connectionFlights[serverID] = nil
    }

    /// The `serverName` convention used for tools exposed to the model: the
    /// endpoint host, falling back to the server id.
    static func toolListingName(for server: ModelContextServer) -> String {
        URL(string: server.endpoint)?.host ?? server.id
    }

    static func configFingerprint(_ server: ModelContextServer) -> String {
        [
            server.type.rawValue,
            server.endpoint,
            server.header,
            String(server.timeout),
        ].joined(separator: "\u{1F}")
    }

    private func updateServerStatus(_ serverId: ModelContextServer.ID, status: ModelContextServer.ConnectionStatus) {
        // 连接状态不进行同步
        edit(identifier: serverId, skipSync: true) {
            $0.update(\.connectionStatus, to: status)
            if status == .connected {
                $0.update(\.lastConnected, to: .now)
            }
        }
    }

    private func updateCapabilities(for serverId: ModelContextServer.ID, hasTools: Bool) {
        // capabilities不进行同步
        edit(identifier: serverId, skipSync: true) {
            $0.assign(\.capabilities, to: StringArrayCodable(hasTools ? ["tools"] : []))
        }
    }

    func listServerTools() async -> [MCPTool] {
        let toolInfos = await getAllTools()
        return toolInfos.map { MCPTool(toolInfo: $0, mcpService: self) }
    }

    @MainActor
    func cachedToolInfos(for serverID: ModelContextServer.ID) -> [MCPToolInfo]? {
        toolInfoCache[serverID]
    }

    @MainActor
    func storeToolInfos(_ infos: [MCPToolInfo], for serverID: ModelContextServer.ID) {
        toolInfoCache[serverID] = infos
    }

    // MARK: - Database Methods

    func updateFromDatabase() {
        servers.send(sdb.modelContextServerList())
    }

    func create(block: Storage.ModelContextServerMakeInitDataBlock? = nil) -> ModelContextServer {
        defer { updateFromDatabase() }
        return sdb.modelContextServerMake(block)
    }

    func server(with identifier: ModelContextServer.ID?) -> ModelContextServer? {
        guard let identifier else { return nil }
        return sdb.modelContextServerWith(identifier)
    }

    func remove(_ identifier: ModelContextServer.ID) {
        defer { updateFromDatabase() }
        sdb.modelContextServerRemove(identifier: identifier)
    }

    func edit(identifier: ModelContextServer.ID, skipSync: Bool = false, block: @escaping (inout ModelContextServer) -> Void) {
        defer { updateFromDatabase() }
        let before = sdb.modelContextServerWith(identifier).map(Self.configFingerprint)
        sdb.modelContextServerEdit(identifier: identifier, skipSync: skipSync, block)
        let after = sdb.modelContextServerWith(identifier).map(Self.configFingerprint)
        if before != after {
            // The stored config changed: the live connection and any in-flight
            // attempt were built against the old one and must not survive.
            // (Status-only writes keep the fingerprint and skip this.)
            Task { @MainActor in
                self.dropConnection(for: identifier)
                self.updateServerStatus(identifier, status: .disconnected)
            }
        }
    }
}

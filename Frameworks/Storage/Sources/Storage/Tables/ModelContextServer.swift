//
//  ModelContextServer.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//

import Foundation
import WCDBSwift

public struct StringArrayCodable: ColumnCodable {
    public let array: [String]

    public init(_ array: [String]) {
        self.array = array
    }

    public init?(with value: WCDBSwift.Value) {
        let data = value.stringValue.data(using: .utf8) ?? Data()
        guard let array = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        self.array = array
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = (try? JSONEncoder().encode(array)) ?? Data()
        return .init(String(data: data, encoding: .utf8) ?? "[]")
    }

    public static var columnType: WCDBSwift.ColumnType {
        .text
    }
}

public final class ModelContextServer: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "ModelContextServer"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = Storage.deviceId
    public package(set) var name: String = ""
    public package(set) var comment: String = ""
    public package(set) var type: ServerType = .http
    public package(set) var endpoint: String = ""
    public package(set) var header: String = ""
    public package(set) var timeout: Int = 60
    public package(set) var isEnabled: Bool = true
    public package(set) var toolsEnabled: EnableCodable = .init()
    public package(set) var resourcesEnabled: EnableCodable = .init()
    public package(set) var templateEnabled: EnableCodable = .init()
    public package(set) var lastConnected: Date?
    public package(set) var connectionStatus: ConnectionStatus = .disconnected
    public package(set) var capabilities: StringArrayCodable = .init([])

    public package(set) var removed: Bool = false
    public package(set) var creation: Date = .now
    public package(set) var modified: Date = .now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ModelContextServer
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: ServerType.http.rawValue)
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(header, isNotNull: true, defaultTo: "")
            BindColumnConstraint(timeout, isNotNull: true, defaultTo: 60)
            BindColumnConstraint(isEnabled, isNotNull: true, defaultTo: true)
            BindColumnConstraint(toolsEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(resourcesEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(templateEnabled, isNotNull: true, defaultTo: EnableCodable())
            BindColumnConstraint(lastConnected, isNotNull: false)
            BindColumnConstraint(connectionStatus, isNotNull: true, defaultTo: ConnectionStatus.disconnected.rawValue)
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: StringArrayCodable([]))

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
        }

        case objectId
        case deviceId
        case name
        case comment
        case type
        case endpoint
        case header
        case timeout
        case isEnabled
        case toolsEnabled
        case templateEnabled
        case resourcesEnabled
        case lastConnected
        case connectionStatus
        case capabilities

        case removed
        case creation
        case modified
    }

    public init(
        name: String = "",
        comment: String = "",
        type: ServerType = .http,
        endpoint: String = "",
        header: String = "",
        timeout: Int = 60,
        isEnabled: Bool = true,
        toolsEnabled: EnableCodable = .init(),
        resourcesEnabled: EnableCodable = .init(),
        templateEnabled: EnableCodable = .init(),
        lastConnected: Date? = nil,
        connectionStatus: ConnectionStatus = .disconnected,
        capabilities: StringArrayCodable = StringArrayCodable([]),
    ) {
        self.name = name
        self.comment = comment
        self.type = type
        self.endpoint = endpoint
        self.header = header
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.toolsEnabled = toolsEnabled
        self.resourcesEnabled = resourcesEnabled
        self.templateEnabled = templateEnabled
        self.lastConnected = lastConnected
        self.connectionStatus = connectionStatus
        self.capabilities = capabilities
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decodeIfPresent(String.self, forKey: .objectId) ?? UUID().uuidString
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? Storage.deviceId
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        type = try container.decodeIfPresent(ServerType.self, forKey: .type) ?? .http
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        header = try container.decodeIfPresent(String.self, forKey: .header) ?? ""
        timeout = try container.decodeIfPresent(Int.self, forKey: .timeout) ?? 60
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        toolsEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .toolsEnabled) ?? .init()
        resourcesEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .resourcesEnabled) ?? .init()
        templateEnabled = try container.decodeIfPresent(EnableCodable.self, forKey: .templateEnabled) ?? .init()
        lastConnected = try container.decodeIfPresent(Date.self, forKey: .lastConnected)
        connectionStatus = try container.decodeIfPresent(ConnectionStatus.self, forKey: .connectionStatus) ?? .disconnected
        capabilities = try container.decodeIfPresent(StringArrayCodable.self, forKey: .capabilities) ?? .init([])

        removed = try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
        creation = try container.decodeIfPresent(Date.self, forKey: .creation) ?? Date()
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ModelContextServer: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ModelContextServer, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<ModelContextServer, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (ModelContextServer) -> Void) {
        block(self)
        markModified()
    }
}

public extension ModelContextServer {
    static func decodeCompatible(from data: Data) throws -> ModelContextServer {
        let decoder = PropertyListDecoder()

        // 尝试旧结构
        if let old = try? decoder.decode(ModelContextServerV1.self, from: data) {
            let new = ModelContextServer()
            new.objectId = old.id
            new.name = old.name
            new.comment = old.comment
            new.type = old.type
            new.endpoint = old.endpoint
            new.header = old.header
            new.timeout = old.timeout
            new.isEnabled = old.isEnabled
            new.toolsEnabled = old.toolsEnabled
            new.resourcesEnabled = old.resourcesEnabled
            new.templateEnabled = old.templateEnabled
            new.lastConnected = old.lastConnected
            new.connectionStatus = old.connectionStatus
            new.capabilities = old.capabilities
            return new
        }

        return try decoder.decode(ModelContextServer.self, from: data)
    }
}

extension ModelContextServer: Equatable {
    public static func == (lhs: ModelContextServer, rhs: ModelContextServer) -> Bool {
        lhs.objectId == rhs.objectId
    }
}

extension ModelContextServer: Hashable {}

public extension ModelContextServer {
    enum ServerType: String, Codable, ColumnCodable, Equatable {
        case http

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }

    enum ConnectionStatus: String, Codable, ColumnCodable, Equatable {
        case disconnected
        case connecting
        case connected
        case failed

        public init?(with value: WCDBSwift.Value) {
            let rawValue = value.stringValue
            self.init(rawValue: rawValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }
    }
}

public extension ModelContextServer {
    struct EnableCodable: Codable, ColumnCodable {
        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(EnableCodable.self, from: data) else {
                return nil
            }
            self = object
        }

        public func archivedValue() -> WCDBSwift.Value {
            do {
                let data = try JSONEncoder().encode(self)
                return .init(data)
            } catch {
                assertionFailure("failed to encode ModelContextServer.EnableCodable: \(error)")
                return .init(Data())
            }
        }

        public static var columnType: WCDBSwift.ColumnType {
            .BLOB
        }

        public var value: [String: Bool] = [:]

        public init() {
            value = [:]
        }

        public init(value: [String: Bool]) {
            self.value = value
        }
    }
}

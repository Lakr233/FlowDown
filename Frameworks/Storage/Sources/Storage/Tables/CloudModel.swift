//
//  CloudModel.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

public enum ModelAPIVersion: String, Codable, CaseIterable, Equatable {
    case oai_completion
    case oai_response
    case claude
}

public final class CloudModel: Identifiable, Codable, Equatable, Hashable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "CloudModel"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = Storage.deviceId
    public package(set) var model_identifier: String = ""
    public package(set) var model_list_endpoint: String = ""
    public package(set) var creation: Date = .now
    public package(set) var modified: Date = .now
    public package(set) var removed: Bool = false
    public package(set) var endpoint: String = ""
    public package(set) var token: String = ""
    public package(set) var headers: [String: String] = [:] // additional headers
    public package(set) var bodyFields: String = "" // additional body fields as JSON string
    public package(set) var api_version: ModelAPIVersion = .oai_completion
    public package(set) var capabilities: Set<ModelCapabilities> = []
    public package(set) var context: ModelContextLength = .short_8k
    public package(set) var temperature_preference: ModelTemperaturePreference = .inherit
    public package(set) var temperature_override: Double?
    // can be used when loading model from our server
    // present to user on the top of the editor page
    public package(set) var comment: String = ""

    // custom display name for the model
    public package(set) var name: String = ""

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = CloudModel
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(model_identifier, isNotNull: true, defaultTo: "")
            BindColumnConstraint(model_list_endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(token, isNotNull: true, defaultTo: "")
            BindColumnConstraint(headers, isNotNull: true, defaultTo: [String: String]())
            BindColumnConstraint(bodyFields, isNotNull: true, defaultTo: "")
            BindColumnConstraint(api_version, isNotNull: true, defaultTo: ModelAPIVersion.oai_completion)
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: Set<ModelCapabilities>())
            BindColumnConstraint(context, isNotNull: true, defaultTo: ModelContextLength.short_8k)
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(temperature_preference, isNotNull: true, defaultTo: ModelTemperaturePreference.inherit)
            BindColumnConstraint(temperature_override, isNotNull: false)

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
        }

        case objectId
        case deviceId
        case model_identifier
        case model_list_endpoint
        case creation
        case endpoint
        case token
        case headers
        case bodyFields
        case capabilities
        case api_version
        case context
        case comment
        case name
        case temperature_preference
        case temperature_override

        case removed
        case modified
    }

    public init(
        deviceId: String,
        objectId: String = UUID().uuidString,
        model_identifier: String = "",
        model_list_endpoint: String = "$INFERENCE_ENDPOINT$/../../models",
        creation: Date = .init(),
        endpoint: String = "",
        token: String = "",
        headers: [String: String] = [
            "HTTP-Referer": "https://flowdown.ai/",
            "X-Title": "FlowDown",
        ],
        bodyFields: String = "",
        context: ModelContextLength = .medium_64k,
        capabilities: Set<ModelCapabilities> = [],
        comment: String = "",
        name: String = "",
        temperature_preference: ModelTemperaturePreference = .inherit,
        temperature_override: Double? = nil
    ) {
        self.deviceId = deviceId
        self.objectId = objectId
        self.model_identifier = model_identifier
        self.model_list_endpoint = model_list_endpoint
        self.creation = creation
        modified = creation
        self.endpoint = endpoint
        self.token = token
        self.headers = headers
        self.bodyFields = bodyFields
        api_version = .oai_completion
        self.capabilities = capabilities
        self.comment = comment
        self.name = name
        self.context = context
        self.temperature_preference = temperature_preference
        self.temperature_override = temperature_override
    }

    public required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        objectId = try container.decodeIfPresent(String.self, forKey: .objectId) ?? UUID().uuidString
        deviceId = try container.decodeIfPresent(String.self, forKey: .deviceId) ?? Storage.deviceId
        model_identifier = try container.decodeIfPresent(String.self, forKey: .model_identifier) ?? ""
        model_list_endpoint = try container.decodeIfPresent(String.self, forKey: .model_list_endpoint) ?? ""
        creation = try container.decodeIfPresent(Date.self, forKey: .creation) ?? Date()
        modified = try container.decodeIfPresent(Date.self, forKey: .modified) ?? Date()
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        bodyFields = try container.decodeIfPresent(String.self, forKey: .bodyFields) ?? ""
        api_version = try container.decodeIfPresent(ModelAPIVersion.self, forKey: .api_version) ?? .oai_completion
        capabilities = try container.decodeIfPresent(Set<ModelCapabilities>.self, forKey: .capabilities) ?? []
        context = try container.decodeIfPresent(ModelContextLength.self, forKey: .context) ?? .short_8k
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        temperature_preference = try container.decodeIfPresent(ModelTemperaturePreference.self, forKey: .temperature_preference) ?? .inherit
        temperature_override = try container.decodeIfPresent(Double.self, forKey: .temperature_override)

        removed = try container.decodeIfPresent(Bool.self, forKey: .removed) ?? false
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }

    public static func == (lhs: CloudModel, rhs: CloudModel) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(model_identifier)
        hasher.combine(model_list_endpoint)
        hasher.combine(creation)
        hasher.combine(modified)
        hasher.combine(endpoint)
        hasher.combine(token)
        hasher.combine(headers)
        hasher.combine(bodyFields)
        hasher.combine(api_version)
        hasher.combine(capabilities)
        hasher.combine(context)
        hasher.combine(comment)
        hasher.combine(name)
        hasher.combine(temperature_preference)
        hasher.combine(temperature_override)
        hasher.combine(removed)
    }
}

extension CloudModel: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<CloudModel, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<CloudModel, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (CloudModel) -> Void) {
        block(self)
        markModified()
    }
}

extension ModelTemperaturePreference: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self = ModelTemperaturePreference(rawValue: text) ?? .inherit
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

extension ModelCapabilities: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self.init(rawValue: text)
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

extension ModelAPIVersion: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self = ModelAPIVersion(rawValue: text) ?? .oai_completion
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

extension ModelContextLength: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        self.init(rawValue: value.intValue)
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .integer64
    }
}

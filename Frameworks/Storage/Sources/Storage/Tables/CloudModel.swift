//
//  CloudModel.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

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
    public package(set) var capabilities: Set<ModelCapabilities> = []
    public package(set) var context: ModelContextLength = .short_8k

    /// this value is deprecated, but should be kept for legacy support
    /// this value can now be configured inside extra body field
    package var temperature_preference: ModelTemperaturePreference = .inherit {
        didSet {
            assert(temperature_preference == .inherit)
            assert(oldValue == temperature_preference)
        }
    }

    public package(set) var response_format: CloudModel.ResponseFormat = .default
    /// can be used when loading model from our server
    /// present to user on the top of the editor page
    public package(set) var comment: String = ""

    /// custom display name for the model
    public package(set) var name: String = ""

    /// 通用扩展容器(plist 编码,key-value 字符串)。模块通过 `ExtensionKey.*` 常量 access。
    /// **永不 rename**。
    public package(set) var ext_data: ExtensionDictionary = .init()

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = CloudModel
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
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
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: Set<ModelCapabilities>())
            BindColumnConstraint(context, isNotNull: true, defaultTo: ModelContextLength.short_8k)
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(temperature_preference, isNotNull: false, defaultTo: ModelTemperaturePreference.inherit)
            BindColumnConstraint(response_format, isNotNull: true, defaultTo: CloudModel.ResponseFormat.default)
            BindColumnConstraint(ext_data, isNotNull: true, defaultTo: ExtensionDictionary())

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
        case context
        case response_format
        case comment
        case name
        case temperature_preference
        case ext_data

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
        response_format: CloudModel.ResponseFormat = .default,
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
        self.capabilities = capabilities
        self.comment = comment
        self.name = name
        self.context = context
        self.response_format = response_format
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
        capabilities = try container.decodeIfPresent(Set<ModelCapabilities>.self, forKey: .capabilities) ?? []
        context = try container.decodeIfPresent(ModelContextLength.self, forKey: .context) ?? .short_8k
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""

        temperature_preference = try container.decodeIfPresent(ModelTemperaturePreference.self, forKey: .temperature_preference) ?? .inherit

        response_format = try container.decodeIfPresent(CloudModel.ResponseFormat.self, forKey: .response_format) ?? .default
        ext_data = try container.decodeIfPresent(ExtensionDictionary.self, forKey: .ext_data) ?? .init()
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
        hasher.combine(capabilities)
        hasher.combine(context)
        hasher.combine(response_format)
        hasher.combine(comment)
        hasher.combine(name)
        hasher.combine(ext_data)
        hasher.combine(removed)
    }
}

public extension CloudModel {
    enum ResponseFormat: String, CaseIterable, Codable {
        case chatCompletions
        case responses

        public static let `default`: CloudModel.ResponseFormat = .chatCompletions
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

extension CloudModel.ResponseFormat: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self = CloudModel.ResponseFormat(rawValue: text) ?? .default
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

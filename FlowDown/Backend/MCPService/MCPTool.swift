//
//  MCPTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import Foundation
import MCP
import Storage

class MCPTool: ModelTool, @unchecked Sendable {
    // MARK: - Properties

    let toolInfo: MCPToolInfo
    let mcpService: MCPService

    // MARK: - Initialization

    init(toolInfo: MCPToolInfo, mcpService: MCPService) {
        self.toolInfo = toolInfo
        self.mcpService = mcpService
        super.init()
    }

    // MARK: - ModelTool Implementation

    override var interfaceName: String {
        toolInfo.name
    }

    override var functionName: String {
        toolInfo.name
    }

    override var definition: ChatRequestBody.Tool {
        let parameters = convertMCPSchemaToJSONValues(toolInfo.inputSchema)
        return .function(
            name: toolInfo.name,
            description: toolInfo.description ?? String(localized: "MCP Tool"),
            parameters: parameters,
            strict: true,
        )
    }

    override var isEnabled: Bool {
        get { true }
        set { assertionFailure() }
    }

    override class var controlObject: ConfigurableObject {
        assertionFailure()
        return .init(
            icon: "hammer",
            title: "MCP Tool",
            explain: "Tools from connected MCP servers",
            key: "MCP.Tools.Enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    // MARK: - Tool Execution

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        var arguments: [String: Value]?
        if !input.isEmpty {
            let data = Data(input.utf8)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                arguments = json.compactMapValues { value in
                    convertJSONValueToMCPValue(value)
                }
            }
        }

        let result = try await mcpService.callTool(
            name: toolInfo.name,
            arguments: arguments,
            from: toolInfo.serverID,
        )

        // isError is optional
        if result.isError == true {
            Logger.network.errorFile("MCP Tool \(toolInfo.name) returned error: \(result.content)")
            let text = "MCP Tool returned error: \(result.content.debugDescription)"
            throw NSError(
                domain: "MCPToolErrorDomain",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: text],
            )
        }

        // later on we process the result content and map audio and image to user attachment
        // so it can be seen by model
        return result.0.serializedRawContent()
    }
}

extension [Tool.Content] {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    func serializedRawContent() -> String {
        do {
            let data = try Self.encoder.encode(self)
            let text = String(data: data, encoding: .utf8)
            return text ?? ""
        } catch {
            Logger.chatService.errorFile("failed to encode tool content: \(error.localizedDescription)")
            return error.localizedDescription
        }
    }

    static func decodeContents(_ input: String?) throws -> [Tool.Content] {
        guard let input else { return [] }
        let data = Data(input.utf8)
        return try decoder.decode([Tool.Content].self, from: data)
    }
}

extension MCPTool {
    /// What a tool advertises when it declares no input at all.
    private static let emptyObjectSchema: [String: AnyCodingValue] = [
        "type": .string("object"),
        "properties": .object([:]),
        "required": .array([]),
        "additionalProperties": .bool(false),
    ]

    private func convertMCPSchemaToJSONValues(_ mcpSchema: Value?) -> [String: AnyCodingValue] {
        guard let mcpSchema,
              case let .object(dict) = convertMCPValueToJSONValue(mcpSchema)
        else {
            return Self.emptyObjectSchema
        }

        // Preserve original values if present, otherwise set default values.
        // `additionalProperties` is coerced by normalizeStrictJSONSchema below.
        var result = dict
        if result["properties"] == nil {
            result["properties"] = .object([:])
        }
        if result["additionalProperties"] == nil {
            result["additionalProperties"] = .bool(false)
        }
        return normalizeStrictJSONSchema(result)
    }

    private func normalizeStrictJSONSchema(_ schema: [String: AnyCodingValue]) -> [String: AnyCodingValue] {
        var schema = schema

        if let additionalProps = schema["additionalProperties"],
           case let .object(obj) = additionalProps, obj.isEmpty
        {
            schema["additionalProperties"] = .bool(false)
        }

        if case let .object(properties) = schema["properties"] {
            var normalizedProperties = properties

            let originalRequired = extractStringArray(from: schema["required"]) ?? []
            let propertyKeys = normalizedProperties.keys.sorted()
            let propertyKeySet = Set(propertyKeys)
            let originalRequiredSet = Set(originalRequired)

            // Strict schemas must list every property as required, so the ones
            // the server left optional have to accept null instead.
            for key in propertyKeySet.subtracting(originalRequiredSet) {
                guard let propertySchema = normalizedProperties[key] else { continue }
                normalizedProperties[key] = allowNullInSchema(propertySchema)
            }

            for (key, value) in normalizedProperties {
                normalizedProperties[key] = normalizeStrictJSONSchemaValue(value)
            }

            schema["properties"] = .object(normalizedProperties)
            schema["required"] = .array(propertyKeys.map { .string($0) })
        } else {
            if schema["required"] == nil {
                schema["required"] = .array([])
            }
        }

        if let itemsValue = schema["items"] {
            schema["items"] = normalizeStrictJSONSchemaValue(itemsValue)
        }

        if let anyOfValue = schema["anyOf"], case let .array(anyOfArray) = anyOfValue {
            schema["anyOf"] = .array(anyOfArray.map { normalizeStrictJSONSchemaValue($0) })
        }

        if let oneOfValue = schema["oneOf"], case let .array(oneOfArray) = oneOfValue {
            schema["oneOf"] = .array(oneOfArray.map { normalizeStrictJSONSchemaValue($0) })
        }

        if let allOfValue = schema["allOf"], case let .array(allOfArray) = allOfValue {
            schema["allOf"] = .array(allOfArray.map { normalizeStrictJSONSchemaValue($0) })
        }

        return schema
    }

    private func normalizeStrictJSONSchemaValue(_ value: AnyCodingValue) -> AnyCodingValue {
        switch value {
        case let .object(dict):
            .object(normalizeStrictJSONSchema(dict))
        case let .array(array):
            .array(array.map { normalizeStrictJSONSchemaValue($0) })
        default:
            value
        }
    }

    private func extractStringArray(from value: AnyCodingValue?) -> [String]? {
        guard let value else { return nil }
        guard case let .array(array) = value else { return nil }
        let strings = array.compactMap { element -> String? in
            guard case let .string(s) = element else { return nil }
            return s
        }
        return strings.count == array.count ? strings : nil
    }

    private func allowNullInSchema(_ schema: AnyCodingValue) -> AnyCodingValue {
        if schemaAllowsNull(schema) {
            return schema
        }

        if case let .object(dict) = schema {
            if let typeValue = dict["type"] {
                switch typeValue {
                case let .string(typeString):
                    var updated = dict
                    updated["type"] = .array([.string(typeString), .string("null")])
                    return .object(updated)
                case let .array(typeArray):
                    var updated = dict
                    var next = typeArray
                    if !next.contains(where: { if case let .string(s) = $0 { s == "null" } else { false } }) {
                        next.append(.string("null"))
                    }
                    updated["type"] = .array(next)
                    return .object(updated)
                default:
                    break
                }
            }

            if let anyOfValue = dict["anyOf"], case let .array(anyOfArray) = anyOfValue {
                var updated = dict
                let hasNull = anyOfArray.contains { schemaAllowsNull($0) }
                if !hasNull {
                    updated["anyOf"] = .array(anyOfArray + [.object(["type": .string("null")])])
                }
                return .object(updated)
            }
        }

        return .object([
            "anyOf": .array([
                schema,
                .object(["type": .string("null")]),
            ]),
        ])
    }

    private func schemaAllowsNull(_ schema: AnyCodingValue) -> Bool {
        guard case let .object(dict) = schema else { return false }

        if let typeValue = dict["type"] {
            switch typeValue {
            case let .string(typeString):
                return typeString == "null"
            case let .array(typeArray):
                return typeArray.contains { element in
                    if case let .string(s) = element { return s == "null" }
                    return false
                }
            default:
                break
            }
        }

        if let anyOfValue = dict["anyOf"], case let .array(anyOfArray) = anyOfValue {
            return anyOfArray.contains { schemaAllowsNull($0) }
        }

        return false
    }

    private func convertMCPValueToJSONValue(_ value: Value) -> AnyCodingValue {
        switch value {
        case let .string(string):
            .string(string)
        case let .int(int):
            .int(int)
        case let .double(double):
            .double(double)
        case let .bool(bool):
            .bool(bool)
        case let .array(values):
            .array(values.map { convertMCPValueToJSONValue($0) })
        case let .object(dict):
            .object(dict.mapValues { convertMCPValueToJSONValue($0) })
        case .null:
            .null(NSNull())
        case let .data(mimeType: mimeType, _):
            .string("[Data: \(mimeType ?? "unknown")]")
        }
    }

    func convertJSONValueToMCPValue(_ jsonValue: Any) -> Value? {
        switch jsonValue {
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if number.isBool {
                return .bool(number.boolValue)
            } else if number.isInteger {
                return .int(number.intValue)
            } else {
                return .double(number.doubleValue)
            }
        case let bool as Bool:
            return .bool(bool)
        case let int as Int:
            return .int(int)
        case let double as Double:
            return .double(double)
        case let array as [Any]:
            let values = array.compactMap { convertJSONValueToMCPValue($0) }
            return .array(values)
        case let dict as [String: Any]:
            let pairs = dict.compactMapValues { convertJSONValueToMCPValue($0) }
            return .object(pairs)
        case is NSNull:
            return .null
        default:
            return nil
        }
    }
}

//
//  MCPTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/10/25.
//

import ChatClientKit
import Foundation
import MCP
import Storage

final class MCPTool: ModelTool, @unchecked Sendable {
    // MARK: - Properties

    let toolInfo: MCPToolInfo
    let mcpService: MCPService

    // MARK: - Initialization

    init(toolInfo: MCPToolInfo, mcpService: MCPService) {
        self.toolInfo = toolInfo
        self.mcpService = mcpService
    }

    // MARK: - ModelTool Implementation

    var interfaceName: String {
        toolInfo.name
    }

    var interfaceIcon: String {
        "server.rack"
    }

    var access: ModelToolAccess {
        .external
    }

    var definition: ChatRequestBody.Tool {
        let parameters = convertMCPSchemaToJSONValues(toolInfo.inputSchema)
        return .function(
            name: toolInfo.name,
            description: toolInfo.description ?? String(localized: "MCP Tool"),
            parameters: parameters,
            strict: true,
        )
    }

    // MARK: - Tool Execution

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let result = try await mcpService.callTool(
            name: toolInfo.name,
            arguments: callArguments(from: arguments.json),
            from: toolInfo.serverID,
        )

        let output = MCPToolContent.output(from: result.content)
        if result.isError == true {
            Logger.network.errorFile("MCP Tool \(toolInfo.name) returned error: \(output.text)")
            throw ModelToolError.failure(
                output.text.isEmpty ? String(localized: "The MCP server reported an error.") : output.text,
            )
        }
        return output
    }
}

extension MCPTool {
    /// Decodes the model's arguments for the server. The strict schema makes
    /// optional parameters required but nullable, so the model sends null for
    /// every one it skips; those keys are dropped so the server sees them as
    /// omitted and applies its own defaults instead of rejecting the null.
    func callArguments(from input: String) -> [String: Value]? {
        guard !input.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any]
        else { return nil }
        var serverRequired: Set<String> = []
        if case let .object(schema) = toolInfo.inputSchema,
           case let .array(required) = schema["required"]
        {
            for case let .string(key) in required {
                serverRequired.insert(key)
            }
        }
        return json
            .filter { !($0.value is NSNull) || serverRequired.contains($0.key) }
            .compactMapValues { convertJSONValueToMCPValue($0) }
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
        return normalizeStrictJSONSchema(result)
    }

    private func normalizeStrictJSONSchema(_ schema: [String: AnyCodingValue]) -> [String: AnyCodingValue] {
        var schema = schema

        // Strict mode requires `additionalProperties: false` on every object,
        // nested ones included. A missing key or `true` allows the same as
        // `{}`, and strict mode cannot honor undeclared keys anyway because
        // every property becomes required below. A non-empty schema (a map
        // type) is left alone.
        switch schema["additionalProperties"] {
        case .none, .some(.bool(true)):
            if isObjectSchema(schema) {
                schema["additionalProperties"] = .bool(false)
            }
        case let .some(.object(obj)) where obj.isEmpty:
            schema["additionalProperties"] = .bool(false)
        default:
            break
        }

        if case let .object(properties) = schema["properties"] {
            var normalizedProperties = properties

            let originalRequired = extractStringArray(from: schema["required"])
            let propertyKeys = normalizedProperties.keys.sorted()
            let originalRequiredSet = Set(originalRequired)

            // Strict schemas must list every property as required, so the ones
            // the server left optional have to accept null instead.
            for (key, value) in properties {
                let nullable = originalRequiredSet.contains(key) ? value : allowNullInSchema(value)
                normalizedProperties[key] = normalizeStrictJSONSchemaValue(nullable)
            }

            schema["properties"] = .object(normalizedProperties)
            schema["required"] = .array(propertyKeys.map { .string($0) })
        } else if schema["required"] == nil {
            schema["required"] = .array([])
        }

        if let itemsValue = schema["items"] {
            schema["items"] = normalizeStrictJSONSchemaValue(itemsValue)
        }

        for combinatorKey in ["anyOf", "oneOf", "allOf"] {
            if case let .array(subschemas) = schema[combinatorKey] {
                schema[combinatorKey] = .array(subschemas.map { normalizeStrictJSONSchemaValue($0) })
            }
        }

        // `$ref` targets have to be strict as well.
        for definitionsKey in ["$defs", "definitions"] {
            if case let .object(definitions) = schema[definitionsKey] {
                schema[definitionsKey] = .object(definitions.mapValues { normalizeStrictJSONSchemaValue($0) })
            }
        }

        return schema
    }

    private func isObjectSchema(_ schema: [String: AnyCodingValue]) -> Bool {
        if schema["properties"] != nil { return true }
        switch schema["type"] {
        case .some(.string("object")):
            return true
        case let .some(.array(types)):
            return types.contains { $0 == .string("object") }
        default:
            return false
        }
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

    private func extractStringArray(from value: AnyCodingValue?) -> [String] {
        guard case let .array(array) = value else { return [] }
        let strings = array.compactMap { element -> String? in
            guard case let .string(s) = element else { return nil }
            return s
        }
        return strings.count == array.count ? strings : []
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
                    updated["type"] = .array(typeArray + [.string("null")])
                    return .object(updated)
                default:
                    break
                }
            }

            if let anyOfValue = dict["anyOf"], case let .array(anyOfArray) = anyOfValue {
                var updated = dict
                updated["anyOf"] = .array(anyOfArray + [.object(["type": .string("null")])])
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
                return typeArray.contains(.string("null"))
            default:
                break
            }
        }

        if case let .array(anyOfArray) = dict["anyOf"] {
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

    private func convertJSONValueToMCPValue(_ jsonValue: Any) -> Value? {
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

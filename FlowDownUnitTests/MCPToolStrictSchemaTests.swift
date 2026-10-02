import ChatClientKit
@testable import FlowDown
import Foundation
import MCP
import Testing

struct MCPToolStrictSchemaTests {
    private let strictFalse: AnyCodingValue = .bool(false)

    @Test
    func strictSchemaNestedObject_closesAdditionalProperties() async throws {
        let parameters = try await strictParameters(for: [
            "type": "object",
            "properties": [
                "filter": [
                    "type": "object",
                    "properties": [
                        "q": ["type": "string"],
                    ],
                ],
            ],
        ])

        let properties = try #require(schemaObject(parameters["properties"]))
        let filter = try #require(schemaObject(properties["filter"]))
        let filterProperties = try #require(schemaObject(filter["properties"]))
        let query = try #require(schemaObject(filterProperties["q"]))

        #expect(parameters["additionalProperties"] == strictFalse)
        #expect(filter["additionalProperties"] == strictFalse)
        #expect(filter["required"] == ["q"])
        // Only objects take the keyword.
        #expect(!query.keys.contains("additionalProperties"))
    }

    @Test
    func strictSchemaRootAllowsAdditionalProperties_becomesClosed() async throws {
        let parameters = try await strictParameters(for: [
            "type": "object",
            "properties": [
                "name": ["type": "string"],
            ],
            "required": ["name"],
            "additionalProperties": true,
        ])

        #expect(parameters["additionalProperties"] == strictFalse)
    }

    @Test
    func strictSchemaDefinitions_areNormalizedLikeProperties() async throws {
        let parameters = try await strictParameters(for: [
            "type": "object",
            "properties": [
                "item": ["$ref": "#/$defs/Item"],
            ],
            "required": ["item"],
            "$defs": [
                "Item": [
                    "type": "object",
                    "properties": [
                        "name": ["type": "string"],
                        "note": ["type": "string"],
                    ],
                    "required": ["name"],
                ],
            ],
        ])

        let definitions = try #require(schemaObject(parameters["$defs"]))
        let item = try #require(schemaObject(definitions["Item"]))

        #expect(item["additionalProperties"] == strictFalse)
        #expect(item["required"] == ["name", "note"])
    }
}

private extension MCPToolStrictSchemaTests {
    func strictParameters(for inputSchema: Value) async throws -> [String: AnyCodingValue] {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let tool = MCPTool(
            toolInfo: MCPToolInfo(
                name: "search",
                inputSchema: inputSchema,
                serverID: "strict-schema-server",
                serverName: "strict.example.com",
            ),
            mcpService: .shared,
        )
        guard case let .function(_, _, parameters, strict) = tool.definition else {
            Issue.record("Expected a function tool definition.")
            return [:]
        }
        #expect(strict == true)
        return try #require(parameters)
    }

    func schemaObject(_ value: AnyCodingValue?) -> [String: AnyCodingValue]? {
        guard case let .object(object) = value else { return nil }
        return object
    }
}

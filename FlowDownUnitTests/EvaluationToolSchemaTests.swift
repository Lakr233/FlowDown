//
//  EvaluationToolSchemaTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct EvaluationToolSchemaTests {
    @Test
    func `bundled tool definitions serialize as object JSON schemas`() throws {
        let representations = EvaluationManifest.Suite.toolCalling.cases.flatMap { caseItem in
            caseItem.content.compactMap { content in
                content.type == .toolDefinition ? content.toolRepresentation : nil
            }
        }

        #expect(!representations.isEmpty)

        for representation in representations {
            let tool = ChatRequestBody.Tool.function(
                name: representation.name,
                description: representation.description,
                parameters: representation.requestParameters,
                strict: false,
            )
            let data = try JSONEncoder().encode(tool)
            let root = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let function = try #require(root["function"] as? [String: Any])
            let parameters = try #require(function["parameters"] as? [String: Any])

            #expect(parameters["type"] as? String == "object")
            #expect(parameters["properties"] is [String: Any])
        }
    }

    @Test
    func `shorthand parameter types become required property schemas`() throws {
        let representation = EvaluationManifest.Suite.Case.ToolRepresentation(
            name: "forecast",
            description: "Get a forecast.",
            parameters: [
                "city": "string",
                "days": "integer",
            ],
        )

        let properties = try #require(objectValue(representation.requestParameters["properties"]))
        let city = try #require(objectValue(properties["city"]))
        let days = try #require(objectValue(properties["days"]))

        #expect(representation.requestParameters["type"] == "object")
        #expect(city["type"] == "string")
        #expect(days["type"] == "integer")
        #expect(representation.requestParameters["required"] == ["city", "days"])
    }

    @Test
    func `complete parameter schemas pass through unchanged`() {
        let schema: [String: AnyCodingValue] = [
            "type": "object",
            "properties": [
                "city": ["type": "string"],
            ],
            "required": ["city"],
        ]
        let representation = EvaluationManifest.Suite.Case.ToolRepresentation(
            name: "forecast",
            description: "Get a forecast.",
            parameters: schema,
        )

        #expect(representation.requestParameters == schema)
    }

    private func objectValue(_ value: AnyCodingValue?) -> [String: AnyCodingValue]? {
        guard case let .object(object) = value else { return nil }
        return object
    }
}

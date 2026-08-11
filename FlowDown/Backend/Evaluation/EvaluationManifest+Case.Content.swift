//
//  EvaluationManifest+Case.Content.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite.Case {
    enum ContentType: String, Codable, Equatable, Hashable, CaseIterable {
        case instruct
        case request
        case reasoning
        case reply
        case toolDefinition
        case toolRequest
        case toolResponse
    }

    class Content: Codable, Equatable {
        let type: ContentType
        let textRepresentation: String?
        let toolRepresentation: ToolRepresentation?
        let imageRepresentation: Data?
        let audioRepresentation: Data?

        init(
            type: ContentType,
            textRepresentation: String? = nil,
            toolRepresentation: ToolRepresentation? = nil,
            imageRepresentation: Data? = nil,
            audioRepresentation: Data? = nil,
        ) {
            self.type = type
            self.textRepresentation = textRepresentation
            self.toolRepresentation = toolRepresentation
            self.imageRepresentation = imageRepresentation
            self.audioRepresentation = audioRepresentation
        }

        static func == (lhs: EvaluationManifest.Suite.Case.Content, rhs: EvaluationManifest.Suite.Case.Content) -> Bool {
            lhs.type == rhs.type
                && lhs.textRepresentation == rhs.textRepresentation
                && lhs.toolRepresentation == rhs.toolRepresentation
                && lhs.imageRepresentation == rhs.imageRepresentation
                && lhs.audioRepresentation == rhs.audioRepresentation
        }
    }

    class ToolRepresentation: Codable, Equatable {
        let name: String
        let description: String
        let parameters: [String: AnyCodingValue]

        var requestParameters: [String: AnyCodingValue] {
            if parameters["type"] == "object" {
                return parameters
            }

            let properties = parameters.mapValues { parameter in
                switch parameter {
                case let .string(type):
                    AnyCodingValue.object(["type": .string(type)])
                default:
                    parameter
                }
            }

            var schema: [String: AnyCodingValue] = [
                "type": "object",
                "properties": .object(properties),
            ]
            if !properties.isEmpty {
                schema["required"] = .array(properties.keys.sorted().map(AnyCodingValue.string))
            }
            return schema
        }

        init(name: String, description: String, parameters: [String: AnyCodingValue]) {
            self.name = name
            self.description = description
            self.parameters = parameters
        }

        static func == (lhs: EvaluationManifest.Suite.Case.ToolRepresentation, rhs: EvaluationManifest.Suite.Case.ToolRepresentation) -> Bool {
            lhs.name == rhs.name
                && lhs.description == rhs.description
                && lhs.parameters == rhs.parameters
        }
    }
}

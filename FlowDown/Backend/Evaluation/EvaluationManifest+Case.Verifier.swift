//
//  EvaluationManifest+Case.Verifier.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite.Case {
    enum Verifier: Equatable, Codable {
        /// does not judge the result programmatically
        case open

        // match content trimming whitespace and newlines
        case match(pattern: String)
        case matchCaseInsensitive(pattern: String)
        case matchRegularExpression(pattern: String)

        // contains condition will search inside output for text
        case contains(pattern: String)
        case containsCaseInsensitive(pattern: String)

        case toolCalled(name: String)
        case tool(parameter: String, value: AnyCodingValue)

        // MARK: - Codable

        private enum CodingKeys: String, CodingKey {
            // New (current) format: one of these keys must exist.
            case open
            case match
            case matchCaseInsensitive
            case matchRegularExpression
            case contains
            case containsCaseInsensitive
            case toolCalled
            case tool

            // Legacy formats
            case type
            case kind
            case verifier
            case pattern
            case name
            case parameter
            case value
            case caseInsensitive
            case isCaseInsensitive
            case regex
            case regularExpression
            case isRegularExpression
        }

        private enum LegacyType: String {
            case open
            case match
            case matchCaseInsensitive
            case matchRegularExpression
            case contains
            case containsCaseInsensitive
            case toolCalled
            case tool
        }

        private struct PatternPayload: Codable, Equatable {
            let pattern: String
        }

        private struct ToolPayload: Codable, Equatable {
            let parameter: String
            let value: AnyCodingValue
        }

        private struct ToolCallPayload: Codable, Equatable {
            let name: String
        }

        init(from decoder: Decoder) throws {
            // Support very old formats encoded as a single string, e.g. "open".
            if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
                if raw == "open" {
                    self = .open
                    return
                }
                // Fallthrough to keyed decoding if not recognized.
            }

            let container = try decoder.container(keyedBy: CodingKeys.self)

            // Current format (one-key tagged union)
            if container.contains(.open) {
                self = .open
                return
            }
            // Pattern-carrying cases all decode the same two shapes: a keyed
            // payload object or a bare string.
            let patternCases: [(CodingKeys, (String) -> Self)] = [
                (.match, Self.match(pattern:)),
                (.matchCaseInsensitive, Self.matchCaseInsensitive(pattern:)),
                (.matchRegularExpression, Self.matchRegularExpression(pattern:)),
                (.contains, Self.contains(pattern:)),
                (.containsCaseInsensitive, Self.containsCaseInsensitive(pattern:)),
            ]
            for (key, makeVerifier) in patternCases where container.contains(key) {
                if let payload = try? container.decode(PatternPayload.self, forKey: key) {
                    self = makeVerifier(payload.pattern)
                    return
                }
                if let pattern = try? container.decode(String.self, forKey: key) {
                    self = makeVerifier(pattern)
                    return
                }
            }
            if container.contains(.toolCalled) {
                if let payload = try? container.decode(ToolCallPayload.self, forKey: .toolCalled) {
                    self = .toolCalled(name: payload.name)
                    return
                }
                if let name = try? container.decode(String.self, forKey: .toolCalled) {
                    self = .toolCalled(name: name)
                    return
                }
            }
            if container.contains(.tool) {
                if let payload = try? container.decode(ToolPayload.self, forKey: .tool) {
                    self = .tool(parameter: payload.parameter, value: payload.value)
                    return
                }

                // A slightly older variant might inline fields at the same level.
                if let parameter = try? container.decode(String.self, forKey: .parameter),
                   let value = try? container.decode(AnyCodingValue.self, forKey: .value)
                {
                    self = .tool(parameter: parameter, value: value)
                    return
                }
            }

            // Legacy format: { "type": "match", "pattern": "..." }
            let typeString = (try? container.decodeIfPresent(String.self, forKey: .type))
                ?? (try? container.decodeIfPresent(String.self, forKey: .kind))
                ?? (try? container.decodeIfPresent(String.self, forKey: .verifier))

            if let typeString, let legacyType = LegacyType(rawValue: typeString) {
                switch legacyType {
                case .open:
                    self = .open
                    return
                case .toolCalled:
                    self = .toolCalled(name: try container.decode(String.self, forKey: .name))
                    return
                case .tool:
                    let parameter = try container.decode(String.self, forKey: .parameter)
                    let value = try container.decode(AnyCodingValue.self, forKey: .value)
                    self = .tool(parameter: parameter, value: value)
                    return
                case .match, .matchCaseInsensitive, .matchRegularExpression, .contains, .containsCaseInsensitive:
                    let pattern = try container.decode(String.self, forKey: .pattern)
                    switch legacyType {
                    case .match:
                        self = .match(pattern: pattern)
                    case .matchCaseInsensitive:
                        self = .matchCaseInsensitive(pattern: pattern)
                    case .matchRegularExpression:
                        self = .matchRegularExpression(pattern: pattern)
                    case .contains:
                        self = .contains(pattern: pattern)
                    case .containsCaseInsensitive:
                        self = .containsCaseInsensitive(pattern: pattern)
                    default:
                        self = .match(pattern: pattern)
                    }
                    return
                }
            }

            // Legacy format observed in stored sessions: { "pattern": "..." }
            // Infer the verifier kind from optional flags; default to `.match`.
            if let pattern = try? container.decodeIfPresent(String.self, forKey: .pattern) {
                let caseInsensitive = (try? container.decodeIfPresent(Bool.self, forKey: .caseInsensitive))
                    ?? (try? container.decodeIfPresent(Bool.self, forKey: .isCaseInsensitive))
                    ?? false
                let regex = (try? container.decodeIfPresent(Bool.self, forKey: .regex))
                    ?? (try? container.decodeIfPresent(Bool.self, forKey: .regularExpression))
                    ?? (try? container.decodeIfPresent(Bool.self, forKey: .isRegularExpression))
                    ?? false

                if regex {
                    self = .matchRegularExpression(pattern: pattern)
                } else if caseInsensitive {
                    self = .matchCaseInsensitive(pattern: pattern)
                } else {
                    self = .match(pattern: pattern)
                }
                return
            }

            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "Unsupported verifier encoding (missing discriminator and legacy fields)",
            ))
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .open:
                try container.encode([String: String](), forKey: .open)
            case let .match(pattern):
                try container.encode(PatternPayload(pattern: pattern), forKey: .match)
            case let .matchCaseInsensitive(pattern):
                try container.encode(PatternPayload(pattern: pattern), forKey: .matchCaseInsensitive)
            case let .matchRegularExpression(pattern):
                try container.encode(PatternPayload(pattern: pattern), forKey: .matchRegularExpression)
            case let .contains(pattern):
                try container.encode(PatternPayload(pattern: pattern), forKey: .contains)
            case let .containsCaseInsensitive(pattern):
                try container.encode(PatternPayload(pattern: pattern), forKey: .containsCaseInsensitive)
            case let .toolCalled(name):
                try container.encode(ToolCallPayload(name: name), forKey: .toolCalled)
            case let .tool(parameter, value):
                try container.encode(ToolPayload(parameter: parameter, value: value), forKey: .tool)
            }
        }
    }
}

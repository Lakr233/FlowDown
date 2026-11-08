//
//  ModelToolReason.swift
//  FlowDown
//

import ChatClientKit
import Foundation

/// Every call carries a short reason, which the approval card and the
/// running call show the user. FlowDown adds it to each tool's parameters
/// and takes it off the arguments before the tool sees them, so it never
/// changes what runs. A tool that already declares a `reason` of its own
/// keeps it: nothing is added, and nothing is taken off.
enum ModelToolReason {
    static let key = "reason"

    static let parameter: AnyCodingValue = .object([
        "type": .string("string"),
        "description": .string(
            "A few words on why you are making this call, shown to the user, e.g. \"Check tomorrow's schedule\". Write it in the user's language.",
        ),
    ])

    /// `definition` with a required `reason` parameter, or nil when the tool
    /// declares its own `reason` and the definition stays as it is.
    static func adding(to definition: ChatRequestBody.Tool) -> ChatRequestBody.Tool? {
        guard case let .function(name, description, parameters, strict) = definition else { return nil }
        var schema = parameters ?? [
            "type": .string("object"),
            "properties": .object([:]),
            "additionalProperties": .bool(false),
        ]
        var properties: [String: AnyCodingValue] = [:]
        if case let .object(existing)? = schema["properties"] {
            properties = existing
        }
        guard properties[key] == nil else { return nil }
        properties[key] = parameter
        schema["properties"] = .object(properties)

        var required: [AnyCodingValue] = []
        if case let .array(existing)? = schema["required"] {
            required = existing
        }
        schema["required"] = .array(required + [.string(key)])
        return .function(name: name, description: description, parameters: schema, strict: strict)
    }

    /// Splits the model's arguments into what the tool reads and the reason
    /// the call gave, nil when it gave none. Arguments that are not a JSON
    /// object pass through as they came.
    static func split(_ json: String) -> (arguments: String, reason: String?) {
        guard var object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let value = object.removeValue(forKey: key)
        else { return (json, nil) }
        let reason = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let arguments = String(data: data, encoding: .utf8)
        else { return (json, reason) }
        return (arguments, reason?.isEmpty == false ? reason : nil)
    }

    /// The reason a stored call gave, for showing it again.
    static func reason(in json: String) -> String? {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any],
              let reason = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty
        else { return nil }
        return reason
    }
}

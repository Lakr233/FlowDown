//
//  ModelToolArguments.swift
//  FlowDown
//

import Foundation

/// A call's arguments as a tool reads them: the JSON object the model
/// wrote, with the `reason` FlowDown asks every call for already taken off.
struct ModelToolArguments: @unchecked Sendable {
    /// The arguments as JSON text, as the tool would have received them.
    let json: String
    /// The decoded object; nil when the model wrote anything but an object.
    let object: [String: Any]?

    init(json: String) {
        self.json = json
        object = (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

    subscript(key: String) -> Any? {
        object?[key]
    }

    /// The string under `key`, nil when it is missing or not a string.
    func string(_ key: String) -> String? {
        object?[key] as? String
    }

    /// The string under `key` with surrounding white space removed, nil
    /// when that leaves it empty.
    func nonEmptyString(_ key: String) -> String? {
        guard let value = string(key)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

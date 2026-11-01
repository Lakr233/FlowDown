//
//  ToolCallDetail.swift
//  FlowDown
//

import Foundation

/// A call as its trace page shows it: each argument by name with its value
/// under it, then the call's result. The arguments arrive as one line of
/// JSON, where a file's content is a single string full of `\n` and `\"`;
/// decoded, a string reads as itself, line breaks and all, and anything
/// else as compact JSON. Arguments that are not a JSON object show as they
/// came.
struct ToolCallDetail: Equatable {
    struct Section: Equatable {
        /// An argument's name, or "Result"; nil for arguments shown as they came.
        let name: String?
        let value: String
    }

    let sections: [Section]

    /// `arguments`: the call's JSON, empty when it has none or they are lost.
    /// `title`: the call's; a `reason` that only repeats it is left out.
    init(arguments: String, result: String, title: String) {
        var sections: [Section]
        let decoded = arguments.isEmpty
            ? [:]
            : (try? JSONSerialization.jsonObject(with: Data(arguments.utf8), options: [.fragmentsAllowed])) as? [String: Any]
        if let decoded {
            sections = decoded
                .filter { name, value in !(name == "reason" && (value as? String) == title) }
                .map { name, value in Section(name: name, value: Self.text(of: value)) }
                .sorted(by: Self.precedes)
        } else {
            sections = [Section(name: nil, value: arguments)]
        }
        if !result.isEmpty {
            sections.append(Section(name: String(localized: "Result"), value: result))
        }
        self.sections = sections
    }

    /// Everything as one plain text: what VoiceOver reads.
    var text: String {
        sections.map { section in section.name.map { $0 + "\n" + section.value } ?? section.value }
            .joined(separator: "\n\n")
    }

    /// A string as itself, anything else as compact JSON.
    private static func text(of value: Any) -> String {
        if let string = value as? String {
            return string
        }
        guard JSONSerialization.isValidJSONObject([value]),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed, .sortedKeys])
        else { return "\(value)" }
        return String(decoding: data, as: UTF8.self)
    }

    /// The reason first, then the values that fit on a line, then the long
    /// ones, such as a file's content; by name within each.
    private static func precedes(_ first: Section, _ second: Section) -> Bool {
        func rank(_ section: Section) -> Int {
            if section.name == "reason" {
                return 0
            }
            return section.value.contains("\n") ? 2 : 1
        }
        let ranks = (rank(first), rank(second))
        return ranks.0 == ranks.1 ? (first.name ?? "") < (second.name ?? "") : ranks.0 < ranks.1
    }
}

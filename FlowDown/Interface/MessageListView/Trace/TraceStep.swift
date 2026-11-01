//
//  TraceStep.swift
//  FlowDown
//

import Foundation
import Storage

/// A step of a summary's trace as the trace sheet lists it: its kind over
/// one line of its detail, and whether it has a page to open. A thought is
/// "Thoughts" over the start of its text; a call is its name over the
/// reason it was given (else the command it runs or what it names, else
/// its result).
struct TraceStep: Hashable {
    let id: String
    let title: String
    /// Empty while the step has nothing to say under its title.
    let subtitle: String
    /// What its page shows, nil when it has nothing to show.
    let body: TraceBody.Key?

    var hasDetail: Bool {
        body != nil
    }

    /// Past this many characters an excerpt ends in an ellipsis: more than
    /// a line holds at any width a sheet has, where a thought or a written
    /// file runs to thousands.
    static let excerptLength = 160

    /// `arguments`: the call's JSON, for a tool step.
    init(_ step: MessageListView.ActivitySummary.Step, arguments: String?) {
        id = step.id
        switch step {
        case let .thought(_, text):
            title = String(localized: "Thoughts")
            subtitle = Self.excerpt(text)
            body = text.isEmpty ? nil : .init(source: text, call: nil)
        case let .tool(_, status):
            let result = status.message.trimmingCharacters(in: .whitespacesAndNewlines)
            let call = TraceBody.Call(title: status.name, arguments: arguments ?? "", result: result)
            let detail = call.detail
            title = status.name
            subtitle = Self.excerpt(Self.callLine(detail))
            body = detail.sections.isEmpty ? nil : .init(source: "", call: call)
        }
    }

    /// The start of `text` on one line: each run of white space, line
    /// breaks included, as one space; past `excerptLength` characters, an
    /// ellipsis.
    static func excerpt(_ text: String) -> String {
        var line = ""
        var length = 0
        var spaced = false
        for character in text {
            guard !character.isWhitespace else {
                spaced = length > 0
                continue
            }
            let added = spaced ? 2 : 1
            guard length + added <= excerptLength else { return line + "…" }
            if spaced {
                line.append(" ")
            }
            line.append(character)
            length += added
            spaced = false
        }
        return line
    }

    /// What a call's row says under its title: the reason it was given,
    /// else its command line, else the file, query or pattern it names,
    /// else its result, else whatever it was given first.
    private static func callLine(_ detail: ToolCallDetail) -> String {
        var values: [String: String] = [:]
        for section in detail.sections {
            if let name = section.name, values[name] == nil {
                values[name] = section.value
            }
        }
        let named = ["reason", "command", "script", "path", "url", "query", "pattern", String(localized: "Result")]
            .lazy.compactMap { values[$0] }
            .first { !$0.allSatisfy(\.isWhitespace) }
        return named ?? detail.sections.first?.value ?? ""
    }
}

//
//  ToolArgumentLabel.swift
//  FlowDown
//

import Foundation

/// What the approval card calls an argument. The built-in tools' arguments
/// have labels in the app's language; any other key, such as an MCP tool's,
/// is spelled out as words, so `end_date` and `endDate` read "End date".
enum ToolArgumentLabel {
    /// An argument as the card shows it; a nil label for arguments that are
    /// not a JSON object, shown as they came.
    struct Row: Equatable {
        let label: String?
        let value: String
    }

    /// The card's rows for `json`: the arguments named in `order` in that
    /// order, any other after them by name. A JSON boolean reads Yes or No;
    /// any other value as the trace page shows it. Empty values are left
    /// out, and so is a `reason` that only repeats the tool's `title`.
    static func rows(of json: String, order: [String], title: String, bundle: Bundle = .main) -> [Row] {
        let decoded = json.isEmpty
            ? [:]
            : (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) as? [String: Any]
        guard let decoded else {
            return json.isEmpty ? [] : [Row(label: nil, value: json)]
        }
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return decoded
            .filter { key, value in !(key == "reason" && (value as? String) == title) }
            .sorted { first, second in
                switch (position[first.key], position[second.key]) {
                case let (a?, b?): a < b
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): first.key < second.key
                }
            }
            .map { key, value in Row(label: text(for: key, bundle: bundle), value: self.value(value, bundle: bundle)) }
            .filter { !$0.value.isEmpty }
    }

    /// A JSON boolean as Yes or No, anything else as the trace page shows it.
    static func value(_ value: Any, bundle: Bundle = .main) -> String {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() {
            return number.boolValue
                ? String(localized: "Yes", bundle: bundle)
                : String(localized: "No", bundle: bundle)
        }
        return ToolCallDetail.text(of: value)
    }

    static func text(for key: String, bundle: Bundle = .main) -> String {
        known(key, bundle: bundle) ?? words(of: key)
    }

    /// The label for an argument of a built-in tool that asks first, nil for
    /// any other key.
    static func known(_ key: String, bundle: Bundle = .main) -> String? {
        switch key {
        case "start_date": String(localized: "Start Date", bundle: bundle)
        case "end_date": String(localized: "End Date", bundle: bundle)
        case "include_all_day_events": String(localized: "Include All-Day Events", bundle: bundle)
        case "ics_file": String(localized: "Event Data", bundle: bundle)
        case "locale": String(localized: "Locale", bundle: bundle)
        case "title": String(localized: "Title", bundle: bundle)
        case "notes": String(localized: "Notes", bundle: bundle)
        case "due_date": String(localized: "Due Date", bundle: bundle)
        case "priority": String(localized: "Priority", bundle: bundle)
        case "list_name": String(localized: "List", bundle: bundle)
        case "reminder_id": String(localized: "Reminder ID", bundle: bundle)
        case "completed": String(localized: "Completed", bundle: bundle)
        case "status": String(localized: "Status", bundle: bundle)
        case "due_start_date": String(localized: "Earliest Due Date", bundle: bundle)
        case "due_end_date": String(localized: "Latest Due Date", bundle: bundle)
        case "alert_start_date": String(localized: "Earliest Alert", bundle: bundle)
        case "alert_end_date": String(localized: "Latest Alert", bundle: bundle)
        case "completed_start_date": String(localized: "Earliest Completion Date", bundle: bundle)
        case "completed_end_date": String(localized: "Latest Completion Date", bundle: bundle)
        case "clear_notes": String(localized: "Clear Notes", bundle: bundle)
        case "clear_due_date": String(localized: "Clear Due Date", bundle: bundle)
        case "clear_priority": String(localized: "Clear Priority", bundle: bundle)
        default: nil
        }
    }

    /// `key` as words with the first letter capitalised: snake_case,
    /// kebab-case and camelCase split at their boundaries, and an acronym
    /// inside a mixed-case key, such as the URL in `repoURL`, kept as it is.
    /// A key with no words in it comes back unchanged.
    static func words(of key: String) -> String {
        let characters = Array(key)
        let isAllCaps = !characters.contains { $0.isLowercase }
        var words: [String] = []
        var current = ""
        for (index, character) in characters.enumerated() {
            if character == "_" || character == "-" || character == "." || character.isWhitespace {
                if !current.isEmpty { words.append(current) }
                current = ""
                continue
            }
            if !current.isEmpty, character.isUppercase {
                let previous = characters[index - 1]
                let next = index + 1 < characters.count ? characters[index + 1] : nil
                // fooBar, foo2Bar, and the String in URLString.
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && next?.isLowercase == true) {
                    words.append(current)
                    current = ""
                }
            }
            current.append(character)
        }
        if !current.isEmpty { words.append(current) }
        guard !words.isEmpty else { return key }

        let sentence = words.map { word in
            let isAcronym = !isAllCaps && word.count > 1 && !word.contains { $0.isLowercase }
            return isAcronym ? word : word.lowercased()
        }
        .joined(separator: " ")
        return sentence.prefix(1).uppercased() + sentence.dropFirst()
    }
}

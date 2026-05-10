//
//  ReminderToolsShared.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import EventKit
import Foundation

enum ReminderToolsShared {
    static let errorDomain = "MTReminderTool"

    enum CalendarMatch: Equatable {
        case useDefault
        case matched(Int)
        case notFound
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        let eventStore = EKEventStore()
        if #available(iOS 17, macCatalyst 17, *) {
            eventStore.requestFullAccessToReminders { granted, _ in completion(granted) }
        } else {
            eventStore.requestAccess(to: .reminder) { granted, _ in completion(granted) }
        }
    }

    static func parseISODate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: trimmed) { return date }

        let isoStandard = ISO8601DateFormatter()
        isoStandard.formatOptions = [.withInternetDateTime]
        if let date = isoStandard.date(from: trimmed) { return date }

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        if let date = dateOnly.date(from: trimmed) { return date }

        return nil
    }

    static func priorityLabel(_ value: Int) -> String {
        switch value {
        case 0: String(localized: "None")
        case 1 ... 4: String(localized: "High")
        case 5: String(localized: "Medium")
        case 6 ... 9: String(localized: "Low")
        default: "\(value)"
        }
    }

    /// Pure decision over a list of calendar titles. Empty name signals "use the
    /// default list", a case-insensitive match returns the index, an unknown
    /// non-empty name returns `.notFound` so callers can surface a clear error
    /// rather than silently falling back to the default list.
    static func matchCalendarTitle(_ name: String, in titles: [String]) -> CalendarMatch {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .useDefault }
        if let index = titles.firstIndex(where: { $0.caseInsensitiveCompare(trimmed) == .orderedSame }) {
            return .matched(index)
        }
        return .notFound
    }

    /// Resolves the user-supplied list name to a concrete `EKCalendar`. Empty
    /// name → the system default reminders calendar. Non-empty unmatched →
    /// throws so a typo doesn't silently land the reminder in the default list.
    static func resolveCalendarRequiringName(
        named name: String,
        eventStore: EKEventStore,
    ) throws -> EKCalendar {
        let candidates = eventStore.calendars(for: .reminder)
        switch matchCalendarTitle(name, in: candidates.map(\.title)) {
        case .useDefault:
            guard let calendar = eventStore.defaultCalendarForNewReminders() else {
                throw NSError(
                    domain: errorDomain, code: 500, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "No default Reminders list is available."),
                    ],
                )
            }
            return calendar
        case let .matched(index):
            return candidates[index]
        case .notFound:
            throw listNotFoundError(name)
        }
    }

    static func authorizationDeniedError() -> NSError {
        NSError(
            domain: errorDomain, code: 403, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Reminders access denied. Please enable Reminders access in Settings."),
            ],
        )
    }

    static func listNotFoundError(_ name: String) -> NSError {
        NSError(
            domain: errorDomain, code: 404, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "No Reminders list named \"\(name)\" found."),
            ],
        )
    }

    static func internalError(_ description: String) -> NSError {
        NSError(
            domain: errorDomain, code: 500, userInfo: [
                NSLocalizedDescriptionKey: description,
            ],
        )
    }

    static func formatReminders(_ reminders: [EKReminder]) -> String {
        if reminders.isEmpty {
            return String(localized: "No reminders found.")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current

        var grouped: [String: [EKReminder]] = [:]
        for reminder in reminders {
            let listName = reminder.calendar?.title ?? String(localized: "Reminders")
            grouped[listName, default: []].append(reminder)
        }

        var lines: [String] = []
        for listName in grouped.keys.sorted() {
            lines.append("# \(listName)")
            lines.append("")

            let items = grouped[listName] ?? []
            let sorted = items.sorted { lhs, rhs in
                let lhsDate = lhs.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                let rhsDate = rhs.dueDateComponents.flatMap { Calendar.current.date(from: $0) } ?? .distantFuture
                return lhsDate < rhsDate
            }

            for reminder in sorted {
                let checkbox = reminder.isCompleted ? "[x]" : "[ ]"
                let title = reminder.title ?? String(localized: "Untitled")
                var meta: [String] = []
                if let components = reminder.dueDateComponents,
                   let date = Calendar.current.date(from: components)
                {
                    meta.append(String(localized: "due: \(dateFormatter.string(from: date))"))
                }
                let alertDates = (reminder.alarms ?? []).compactMap(\.absoluteDate)
                if !alertDates.isEmpty {
                    let formatted = alertDates
                        .map { dateFormatter.string(from: $0) }
                        .joined(separator: ", ")
                    meta.append(String(localized: "alert: \(formatted)"))
                }
                if reminder.priority != 0 {
                    meta.append(String(localized: "priority: \(priorityLabel(reminder.priority))"))
                }
                let metaPart = meta.isEmpty ? "" : " (" + meta.joined(separator: ", ") + ")"
                lines.append("- \(checkbox) \(title)\(metaPart) [id: \(reminder.calendarItemIdentifier)]")

                if let notes = reminder.notes, !notes.isEmpty {
                    let firstLine = notes.split(whereSeparator: \.isNewline).first.map(String.init) ?? notes
                    lines.append("  📝 \(firstLine)")
                }
            }
            lines.append("")
        }

        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func fetchReminder(id: String, eventStore: EKEventStore) -> EKReminder? {
        eventStore.calendarItem(withIdentifier: id) as? EKReminder
    }
}

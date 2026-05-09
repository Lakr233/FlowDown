//
//  ReminderToolsShared.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import EventKit
import Foundation

enum ReminderToolsShared {
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

    static func resolveCalendar(named name: String, eventStore: EKEventStore) -> EKCalendar? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            let candidates = eventStore.calendars(for: .reminder)
            if let match = candidates.first(where: { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }) {
                return match
            }
        }
        return eventStore.defaultCalendarForNewReminders()
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

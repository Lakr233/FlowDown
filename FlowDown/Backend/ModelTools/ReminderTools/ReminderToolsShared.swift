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

    /// Every reminder tool runs this before it touches `EKEventStore`: it
    /// asks for access and throws `authorizationDeniedError()` when the user
    /// said no.
    static func requireAccess() async throws {
        guard await requestAccess() else {
            throw authorizationDeniedError()
        }
    }

    /// Asks for Reminders access using whichever API the running OS provides.
    private static func requestAccess() async -> Bool {
        let eventStore = EKEventStore()
        if #available(iOS 17, macCatalyst 17, *) {
            return (try? await eventStore.requestFullAccessToReminders()) ?? false
        } else {
            return (try? await eventStore.requestAccess(to: .reminder)) ?? false
        }
    }

    /// Whether Reminders access is already granted. Unlike `requestAccess()`
    /// it never asks the user.
    static var hasAccess: Bool {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        if #available(iOS 17, macCatalyst 17, *) {
            return status == .fullAccess
        } else {
            return status == .authorized
        }
    }

    /// Runs `body` on the reminder `id` names, to describe a call on its
    /// approval card. Reads only when access is already granted, so
    /// describing a call never asks for it; nil when access is missing or
    /// no reminder has that id.
    static func withExistingReminder<Value>(id: String, _ body: (EKReminder) -> Value) -> Value? {
        guard hasAccess else { return nil }
        let eventStore = EKEventStore()
        // A fetched reminder reads through its store, so keep the store alive
        // until `body` is done with it.
        return withExtendedLifetime(eventStore) {
            fetchReminder(id: id, eventStore: eventStore).map(body)
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
        if isBareDate(trimmed), let date = dateOnly.date(from: trimmed) { return date }

        return nil
    }

    /// A bare date such as `2026-10-05` names a day on the user's calendar,
    /// not an instant. Returns the start of that day in `calendar`'s time
    /// zone, or nil when the string carries a time or does not parse.
    static func parseLocalDay(_ string: String, calendar: Calendar = .current) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isBareDate(trimmed) else { return nil }

        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]
        dateOnly.timeZone = calendar.timeZone
        return dateOnly.date(from: trimmed)
    }

    /// Due date components for a reminder. A bare date becomes an all-day
    /// due date on that local day; a timestamp keeps its local hour and minute.
    static func dueDateComponents(from string: String, calendar: Calendar = .current) -> DateComponents? {
        if let day = parseLocalDay(string, calendar: calendar) {
            return calendar.dateComponents([.year, .month, .day], from: day)
        }
        guard let date = parseISODate(string) else { return nil }
        return calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    }

    /// The `.withFullDate` formatter reads the leading date and ignores any
    /// trailing time, so a timestamp without an offset would silently lose its
    /// time. Only an exact `yyyy-MM-dd` counts as a bare date.
    private static func isBareDate(_ trimmed: String) -> Bool {
        trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
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
                    domain: errorDomain,
                    code: 500,
                    userInfo: [
                        NSLocalizedDescriptionKey:  "No default Reminders list is available.",
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
            domain: errorDomain,
            code: 403,
            userInfo: [
                NSLocalizedDescriptionKey:
                    String(localized: "Reminders access denied. Please enable Reminders access in Settings."),
            ],
        )
    }

    static func listNotFoundError(_ name: String) -> NSError {
        NSError(
            domain: errorDomain,
            code: 404,
            userInfo: [
                NSLocalizedDescriptionKey: String(localized: "No Reminders list named \"\(name)\" found."),
            ],
        )
    }

    static func displayTitle(of reminder: EKReminder) -> String {
        reminder.title ?? String(localized: "Untitled")
    }

    static func displayListName(of reminder: EKReminder) -> String {
        reminder.calendar?.title ?? String(localized: "Reminders")
    }

    static func dueDate(of reminder: EKReminder) -> Date? {
        reminder.dueDateComponents.flatMap { Calendar.current.date(from: $0) }
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
            let listName = displayListName(of: reminder)
            grouped[listName, default: []].append(reminder)
        }

        var lines: [String] = []
        for (listName, items) in grouped.sorted(by: { $0.key < $1.key }) {
            lines.append("# \(listName)")
            lines.append("")

            let sorted = items.sorted { lhs, rhs in
                (dueDate(of: lhs) ?? .distantFuture) < (dueDate(of: rhs) ?? .distantFuture)
            }

            for reminder in sorted {
                let checkbox = reminder.isCompleted ? "[x]" : "[ ]"
                let title = displayTitle(of: reminder)
                var meta: [String] = []
                if let date = dueDate(of: reminder) {
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

    static func requireReminder(id: String, eventStore: EKEventStore) throws -> EKReminder {
        guard let reminder = fetchReminder(id: id, eventStore: eventStore) else {
            throw ModelToolError.failure(String(localized: "Reminder with id \(id) not found."))
        }
        return reminder
    }
}

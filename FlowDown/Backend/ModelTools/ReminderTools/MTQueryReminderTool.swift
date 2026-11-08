//
//  MTQueryReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation

final class MTQueryReminderTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Query Reminders")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "query_reminders",
            description: """
            Query reminders by completion status, list name, and independent date ranges over due date, alarm time and completion date.
            A range becomes active once either bound is set; active ranges are ANDed, and a reminder lacking the field a range targets fails it (no alarms fails alert_*, incomplete fails completed_*). The alert range matches when any alarm falls inside it.
            All dates are ISO 8601 UTC; each range spans at most 365 days with start on or before end. Pass empty strings to skip a range.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "status": [
                        "type": "string",
                        "enum": ["incomplete", "completed", "all"],
                        "description": "Which reminders to return.",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Restrict to one Reminders list. Empty queries all lists.",
                    ],
                    "due_start_date": [
                        "type": "string",
                        "description": "Due date lower bound, ISO 8601 UTC. Empty skips.",
                    ],
                    "due_end_date": [
                        "type": "string",
                        "description": "Due date upper bound, ISO 8601 UTC. Empty skips.",
                    ],
                    "alert_start_date": [
                        "type": "string",
                        "description": "Alarm time lower bound, ISO 8601 UTC. Empty skips.",
                    ],
                    "alert_end_date": [
                        "type": "string",
                        "description": "Alarm time upper bound, ISO 8601 UTC. Empty skips.",
                    ],
                    "completed_start_date": [
                        "type": "string",
                        "description": "Completion date lower bound, ISO 8601 UTC. Empty skips.",
                    ],
                    "completed_end_date": [
                        "type": "string",
                        "description": "Completion date upper bound, ISO 8601 UTC. Empty skips.",
                    ],
                ],
                "required": [
                    "status", "list_name",
                    "due_start_date", "due_end_date",
                    "alert_start_date", "alert_end_date",
                    "completed_start_date", "completed_end_date",
                ],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Query Reminders",
            explain: "Allows LLM to read your reminders.",
            key: "wiki.qaq.ModelTools.QueryReminderTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var access: ModelToolAccess {
        .privateData
    }

    var group: ModelToolGroup? {
        .reminders
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let json = arguments.object else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid input parameters"))
        }

        let status = (json["status"] as? String) ?? "incomplete"
        let listName = (json["list_name"] as? String) ?? ""

        let dueRange = try Self.parseRange(
            prefix: "due",
            startString: (json["due_start_date"] as? String) ?? "",
            endString: (json["due_end_date"] as? String) ?? "",
        )
        let alertRange = try Self.parseRange(
            prefix: "alert",
            startString: (json["alert_start_date"] as? String) ?? "",
            endString: (json["alert_end_date"] as? String) ?? "",
        )
        let completedRange = try Self.parseRange(
            prefix: "completed",
            startString: (json["completed_start_date"] as? String) ?? "",
            endString: (json["completed_end_date"] as? String) ?? "",
        )

        try await ReminderToolsShared.requireAccess()

        let eventStore = EKEventStore()
        let calendars: [EKCalendar]? = if listName.isEmpty {
            nil
        } else {
            try [ReminderToolsShared.resolveCalendarRequiringName(
                named: listName,
                eventStore: eventStore,
            )]
        }

        let result = await fetchReminders(
            eventStore: eventStore,
            calendars: calendars,
            status: status,
            due: dueRange,
            alert: alertRange,
            completed: completedRange,
        )
        return ModelToolOutput(text: result)
    }

    struct DateRange: Equatable {
        let start: Date?
        let end: Date?

        var isActive: Bool { start != nil || end != nil }

        func contains(_ date: Date) -> Bool {
            if let start, date < start { return false }
            if let end, date > end { return false }
            return true
        }
    }

    static func parseRange(
        prefix: String,
        startString: String,
        endString: String,
        calendar: Calendar = .current,
    ) throws -> DateRange {
        // A bare date bound covers that whole local day: the start is its local
        // midnight and the end the last instant before the next local midnight.
        let start: Date?
        if startString.isEmpty {
            start = nil
        } else {
            start = ReminderToolsShared.parseLocalDay(startString, calendar: calendar)
                ?? ReminderToolsShared.parseISODate(startString)
        }
        let end: Date?
        if endString.isEmpty {
            end = nil
        } else if let day = ReminderToolsShared.parseLocalDay(endString, calendar: calendar),
                  let nextDay = calendar.date(byAdding: .day, value: 1, to: day)
        {
            end = Date(timeIntervalSinceReferenceDate: nextDay.timeIntervalSinceReferenceDate.nextDown)
        } else {
            end = ReminderToolsShared.parseISODate(endString)
        }

        if !startString.isEmpty, start == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey:
                    "\(prefix): " + String(localized: "Invalid start_date format. Use ISO 8601 UTC."),
            ])
        }
        if !endString.isEmpty, end == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey:
                    "\(prefix): " + String(localized: "Invalid end_date format. Use ISO 8601 UTC."),
            ])
        }

        if let start, let end {
            if end < start {
                throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey:
                        "\(prefix): " + String(localized: "start_date must be on or before end_date."),
                ])
            }
            let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
            if days > 365 {
                throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "\(prefix): " + String(localized: "Date range cannot exceed 365 days"),
                ])
            }
        }

        return DateRange(start: start, end: end)
    }

    /// The matching reminders, formatted for the model.
    private func fetchReminders(
        eventStore: EKEventStore,
        calendars: [EKCalendar]?,
        status: String,
        due: DateRange,
        alert: DateRange,
        completed: DateRange,
    ) async -> String {
        // EventKit's status-specific predicates can take a date range, but they
        // bind it to a specific field (due date for incomplete, completion date
        // for completed). The tool exposes three independent ranges that are
        // ANDed together, so we always fetch the full status set and apply the
        // ranges in Swift below.
        let predicate: NSPredicate
        switch status {
        case "completed":
            predicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: nil,
                ending: nil,
                calendars: calendars,
            )
        case "all":
            predicate = eventStore.predicateForReminders(in: calendars)
        default:
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: nil,
                ending: nil,
                calendars: calendars,
            )
        }

        // EventKit calls back on a background queue; filter and format there
        // so only the finished text leaves the callback.
        return await withCheckedContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                let filtered = Self.applyDateFilters(
                    reminders ?? [],
                    due: due,
                    alert: alert,
                    completed: completed,
                )
                continuation.resume(returning: ReminderToolsShared.formatReminders(filtered))
            }
        }
    }

    static func applyDateFilters(
        _ reminders: [EKReminder],
        due: DateRange,
        alert: DateRange,
        completed: DateRange,
    ) -> [EKReminder] {
        if !due.isActive, !alert.isActive, !completed.isActive {
            return reminders
        }

        return reminders.filter { reminder in
            if due.isActive {
                guard let components = reminder.dueDateComponents,
                      let date = Calendar.current.date(from: components),
                      due.contains(date)
                else { return false }
            }
            if alert.isActive {
                let alarmDates = (reminder.alarms ?? []).compactMap(\.absoluteDate)
                guard alarmDates.contains(where: alert.contains) else { return false }
            }
            if completed.isActive {
                guard let date = reminder.completionDate, completed.contains(date) else { return false }
            }
            return true
        }
    }
}

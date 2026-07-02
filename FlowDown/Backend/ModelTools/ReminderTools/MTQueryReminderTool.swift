//
//  MTQueryReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation
import UIKit

class MTQueryReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "query reminders from user's system Reminders"
    }

    override var interfaceName: String {
        String(localized: "Query Reminders")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "query_reminders",
            description: """
            Query reminders from the user's system Reminders. Filter by completion status, by Reminders list name, and optionally by independent date ranges on the reminder's due date, alarm/alert time, and completion date.
            Each range is applied independently with AND semantics: a reminder is returned only when every *active* range matches (a range is active when at least one of its bounds is non-empty). Reminders missing the field that an active range targets are excluded by that range (e.g. an incomplete reminder is excluded by any active completed_* range; a reminder with no alarms is excluded by any active alert_* range).
            The alert range matches when *any* alarm on the reminder has an absolute date inside the range. The completed range is only meaningful for completed reminders.
            Each individual range cannot exceed 365 days, and start must be on or before end. All dates are ISO 8601 UTC.
            Pass empty strings for any range you don't want to apply.
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
                        "description": "Restrict to a single Reminders list by name. Pass empty string to query all lists.",
                    ],
                    "due_start_date": [
                        "type": "string",
                        "description": "Lower bound for the reminder's due date, ISO 8601 UTC. Pass empty string to skip.",
                    ],
                    "due_end_date": [
                        "type": "string",
                        "description": "Upper bound for the reminder's due date, ISO 8601 UTC. Pass empty string to skip.",
                    ],
                    "alert_start_date": [
                        "type": "string",
                        "description": "Lower bound for any alarm/alert time on the reminder, ISO 8601 UTC. Pass empty string to skip.",
                    ],
                    "alert_end_date": [
                        "type": "string",
                        "description": "Upper bound for any alarm/alert time on the reminder, ISO 8601 UTC. Pass empty string to skip.",
                    ],
                    "completed_start_date": [
                        "type": "string",
                        "description": "Lower bound for the reminder's completion date, ISO 8601 UTC. Pass empty string to skip.",
                    ],
                    "completed_end_date": [
                        "type": "string",
                        "description": "Upper bound for the reminder's completion date, ISO 8601 UTC. Pass empty string to skip.",
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

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Query Reminders",
            explain: "Allows LLM to read your reminders.",
            key: "wiki.qaq.ModelTools.QueryReminderTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NSError(
                domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid input parameters"),
                ],
            )
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

        guard let viewController = await view.parentViewController else {
            throw NSError(domain: "MTQueryReminderTool", code: 500, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
            ])
        }

        return try await queryWithUserInteraction(
            status: status,
            listName: listName,
            due: dueRange,
            alert: alertRange,
            completed: completedRange,
            controller: viewController,
        )
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
    ) throws -> DateRange {
        let start = startString.isEmpty ? nil : ReminderToolsShared.parseISODate(startString)
        let end = endString.isEmpty ? nil : ReminderToolsShared.parseISODate(endString)

        if !startString.isEmpty, start == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "\(prefix): " + String(localized: "Invalid start_date format. Use ISO 8601 UTC."),
            ])
        }
        if !endString.isEmpty, end == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "\(prefix): " + String(localized: "Invalid end_date format. Use ISO 8601 UTC."),
            ])
        }

        if let start, let end {
            if end < start {
                throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "\(prefix): " + String(localized: "start_date must be on or before end_date."),
                ])
            }
            let days = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            if days > 365 {
                throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: "\(prefix): " + String(localized: "Date range cannot exceed 365 days"),
                ])
            }
        }

        return DateRange(start: start, end: end)
    }

    @MainActor
    private func queryWithUserInteraction(
        status: String,
        listName: String,
        due: DateRange,
        alert: DateRange,
        completed: DateRange,
        controller: UIViewController,
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            ReminderToolsShared.requestAccess { [weak self] granted in
                Task { @MainActor in
                    guard let self else {
                        cont.resume(throwing: ReminderToolsShared.internalError("Reminder tool was deallocated before completion."))
                        return
                    }
                    guard granted else {
                        cont.resume(throwing: ReminderToolsShared.authorizationDeniedError())
                        return
                    }

                    let eventStore = EKEventStore()
                    let calendars: [EKCalendar]?
                    if listName.isEmpty {
                        calendars = nil
                    } else {
                        do {
                            calendars = [try ReminderToolsShared.resolveCalendarRequiringName(
                                named: listName,
                                eventStore: eventStore,
                            )]
                        } catch {
                            cont.resume(throwing: error)
                            return
                        }
                    }

                    self.fetchReminders(
                        eventStore: eventStore,
                        calendars: calendars,
                        status: status,
                        due: due,
                        alert: alert,
                        completed: completed,
                    ) { [weak self] result in
                        // EventKit's fetchReminders callback fires on a background
                        // queue; hop back to the main actor before touching UI.
                        Task { @MainActor [weak self] in
                            guard let self else {
                                cont.resume(returning: result)
                                return
                            }
                            self.showResults(result: result, controller: controller, continuation: cont)
                        }
                    }
                }
            }
        }
    }

    private func fetchReminders(
        eventStore: EKEventStore,
        calendars: [EKCalendar]?,
        status: String,
        due: DateRange,
        alert: DateRange,
        completed: DateRange,
        completion: @escaping (String) -> Void,
    ) {
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

        eventStore.fetchReminders(matching: predicate) { reminders in
            let list = reminders ?? []
            let filtered = Self.applyDateFilters(
                list,
                due: due,
                alert: alert,
                completed: completed,
            )
            completion(ReminderToolsShared.formatReminders(filtered))
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

    @MainActor
    private func showResults(
        result: String,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        let preview = formatPreview(result)

        let alert = AlertViewController(
            title: "Reminders",
            message: preview,
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled sharing reminders."),
                    ]))
                }
            }
            context.addAction(title: "Share", attribute: .accent) {
                context.dispose {
                    continuation.resume(returning: result)
                }
            }
        }

        guard controller.presentedViewController == nil else {
            continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Tool execution failed: authorization dialog is already presented."),
            ]))
            return
        }

        controller.present(alert, animated: true) {
            guard alert.isVisible else {
                continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Failed to display results dialog."),
                ]))
                return
            }
        }
    }

    private func formatPreview(_ markdown: String) -> String {
        var displayLines: [String] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var lineCount = 0
        var truncated = false
        for line in lines {
            lineCount += 1
            if lineCount > 8 {
                truncated = true
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2))
                displayLines.append(title)
                displayLines.append(String(repeating: "-", count: title.count))
            } else if trimmed.hasPrefix("- ") {
                var line = String(trimmed.dropFirst(2))
                if let idRange = line.range(of: " [id: ") {
                    line = String(line[..<idRange.lowerBound])
                }
                displayLines.append("• " + line)
            } else if !trimmed.isEmpty {
                displayLines.append(trimmed)
            }
        }

        if truncated {
            displayLines.append("\n... \(String(localized: "More reminders available"))")
        }

        return displayLines.joined(separator: "\n")
    }
}

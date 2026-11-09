//
//  MTAddReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation

final class MTAddReminderTool: ConfigurableModelTool, @unchecked Sendable {
    /// The reminder a call asks for.
    private struct Request {
        let title: String
        let notes: String
        let dueDateComponents: DateComponents?
        let priority: Int
        let listName: String

        /// The lines that describe the reminder on the approval card.
        var summaryLines: [String] {
            var lines = [String(localized: "Title: \(title)")]
            if !notes.isEmpty {
                lines.append(String(localized: "Notes: \(notes)"))
            }
            if let dueDateComponents, let dueDate = Calendar.current.date(from: dueDateComponents) {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                // A date-only due date is an all-day reminder; showing midnight
                // would suggest a time the user never gave.
                formatter.timeStyle = dueDateComponents.hour == nil ? .none : .short
                lines.append(String(localized: "Due: \(formatter.string(from: dueDate))"))
            }
            if priority != 0 {
                lines.append(String(localized: "Priority: \(ReminderToolsShared.priorityLabel(priority))"))
            }
            if !listName.isEmpty {
                lines.append(String(localized: "List: \(listName)"))
            }
            return lines
        }
    }

    var interfaceName: String {
        String(localized: "Add to Reminders")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "add_reminder",
            description: """
            Create a reminder. Convert dates to ISO 8601 UTC (yyyy-MM-dd'T'HH:mm:ss'Z') yourself; do not ask the user.
            Leave optional fields as an empty string, priority as 0.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Reminder title, non-empty.",
                    ],
                    "notes": [
                        "type": "string",
                        "description": "Notes. Empty for none.",
                    ],
                    "due_date": [
                        "type": "string",
                        "description": "Due date, ISO 8601 UTC. Empty for none.",
                    ],
                    "priority": [
                        "type": "integer",
                        "description": "0 none, 1 high, 5 medium, 9 low.",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Reminders list to add to. Empty for the default list.",
                    ],
                ],
                "required": ["title", "notes", "due_date", "priority", "list_name"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Add to Reminders",
            explain: "Allows LLM to create reminders in your system Reminders.",
            key: "wiki.qaq.ModelTools.AddReminderTool.enabled",
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

    func approvalSummary(for arguments: ModelToolArguments) async -> String? {
        guard let request = try? parse(arguments) else { return nil }
        return request.summaryLines.joined(separator: "\n")
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let request = try parse(arguments)
        try await ReminderToolsShared.requireAccess()

        let eventStore = EKEventStore()
        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = request.title
        if !request.notes.isEmpty { reminder.notes = request.notes }
        if let dueDateComponents = request.dueDateComponents {
            reminder.dueDateComponents = dueDateComponents
        }
        if request.priority != 0 { reminder.priority = request.priority }
        reminder.calendar = try ReminderToolsShared.resolveCalendarRequiringName(
            named: request.listName,
            eventStore: eventStore,
        )
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw ModelToolError.failure(
                String(localized: "Failed to add reminder: \(error.localizedDescription)"),
            )
        }

        let id = reminder.calendarItemIdentifier
        return ModelToolOutput(text: String(localized: "Reminder added: \(request.title) [id: \(id)]"))
    }

    private func parse(_ arguments: ModelToolArguments) throws -> Request {
        guard let title = arguments.string("title"), !title.isEmpty else {
            throw ModelToolError.invalidArguments(String(localized: "A non-empty title is required."))
        }

        let notes = arguments.string("notes") ?? ""
        let dueDateString = arguments.string("due_date") ?? ""
        let priority = arguments["priority"] as? Int ?? 0
        let listName = arguments.string("list_name") ?? ""

        let dueDateComponents: DateComponents? = dueDateString.isEmpty
            ? nil
            : ReminderToolsShared.dueDateComponents(from: dueDateString)
        if !dueDateString.isEmpty, dueDateComponents == nil {
            throw ModelToolError.invalidArguments(String(localized: "Invalid due_date format. Use ISO 8601 UTC."))
        }

        return Request(
            title: title,
            notes: notes,
            dueDateComponents: dueDateComponents,
            priority: priority,
            listName: listName,
        )
    }
}

//
//  MTUpdateReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation

final class MTUpdateReminderTool: ConfigurableModelTool, @unchecked Sendable {
    /// The reminder a call names, and the changes it asks for.
    private struct Request {
        let reminderId: String
        let changes: ParsedChanges
    }

    var interfaceName: String {
        String(localized: "Update Reminder")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "update_reminder",
            description: """
            Update a reminder; get reminder_id from query_reminders first.
            Leave a field alone with an empty string (-1 for priority) and clear_*=false; erase it with clear_*=true and that same empty value. Sending a value together with clear_*=true is rejected. list_name has no clear flag since every reminder lives in a list. Dates are ISO 8601 UTC.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier from query_reminders.",
                    ],
                    "title": [
                        "type": "string",
                        "description": "New title. Empty leaves it unchanged.",
                    ],
                    "notes": [
                        "type": "string",
                        "description": "New notes. Empty leaves them unchanged.",
                    ],
                    "clear_notes": [
                        "type": "boolean",
                        "description": "true removes the notes; cannot pair with a notes value.",
                    ],
                    "due_date": [
                        "type": "string",
                        "description": "New due date, ISO 8601 UTC. Empty leaves it unchanged.",
                    ],
                    "clear_due_date": [
                        "type": "boolean",
                        "description": "true removes the due date; cannot pair with a due_date value.",
                    ],
                    "priority": [
                        "type": "integer",
                        "description": "New priority: 0 none, 1 high, 5 medium, 9 low. -1 leaves it unchanged.",
                    ],
                    "clear_priority": [
                        "type": "boolean",
                        "description": "true clears priority to none; cannot pair with a priority >= 0.",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Move to this existing Reminders list. Empty leaves it unchanged.",
                    ],
                ],
                "required": [
                    "reminder_id",
                    "title",
                    "notes", "clear_notes",
                    "due_date", "clear_due_date",
                    "priority", "clear_priority",
                    "list_name",
                ],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Update Reminder",
            explain: "Allows LLM to modify reminders, including marking them as complete.",
            key: "wiki.qaq.ModelTools.UpdateReminderTool.enabled",
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
        return ReminderToolsShared.withExistingReminder(id: request.reminderId) { reminder in
            let title = reminder.title ?? String(localized: "Untitled")
            let summary = Self.summarizeChanges(request.changes, currentTitle: reminder.title)
            guard !summary.isEmpty else { return title }
            return title + "\n\n" + summary.joined(separator: "\n")
        }
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let request = try parse(arguments)
        try await ReminderToolsShared.requireAccess()

        let eventStore = EKEventStore()
        guard let reminder = ReminderToolsShared.fetchReminder(id: request.reminderId, eventStore: eventStore) else {
            throw ModelToolError.failure(String(localized: "Reminder with id \(request.reminderId) not found."))
        }

        let changes = request.changes
        guard !changes.isEmpty else {
            return ModelToolOutput(text: String(localized: "No changes specified; reminder left untouched."))
        }

        if let newTitle = changes.newTitle { reminder.title = newTitle }
        if changes.clearNotes {
            reminder.notes = nil
        } else if let newNotes = changes.newNotes {
            reminder.notes = newNotes
        }
        if changes.clearDueDate {
            reminder.dueDateComponents = nil
        } else if let newDueDate = changes.newDueDate,
                  let components = ReminderToolsShared.dueDateComponents(from: newDueDate)
        {
            reminder.dueDateComponents = components
        }
        if changes.clearPriority {
            reminder.priority = 0
        } else if let newPriority = changes.newPriority {
            reminder.priority = newPriority
        }
        do {
            if let newListName = changes.newListName {
                reminder.calendar = try ReminderToolsShared.resolveCalendarRequiringName(
                    named: newListName,
                    eventStore: eventStore,
                )
            }
            try eventStore.save(reminder, commit: true)
        } catch let error as NSError where error.domain == ReminderToolsShared.errorDomain {
            throw error
        } catch {
            throw ModelToolError.failure(
                String(localized: "Failed to update reminder: \(error.localizedDescription)"),
            )
        }

        return ModelToolOutput(text: String(localized: "Reminder updated: \(reminder.title ?? "-")"))
    }

    private func parse(_ arguments: ModelToolArguments) throws -> Request {
        guard let json = arguments.object,
              let reminderId = json["reminder_id"] as? String, !reminderId.isEmpty
        else {
            throw ModelToolError.invalidArguments(String(localized: "reminder_id is required."))
        }
        return try Request(reminderId: reminderId, changes: Self.parseChanges(from: json))
    }

    struct ParsedChanges: Equatable {
        var newTitle: String?
        var newNotes: String?
        var clearNotes: Bool
        var newDueDate: String?
        var clearDueDate: Bool
        var newPriority: Int?
        var clearPriority: Bool
        var newListName: String?

        var isEmpty: Bool {
            newTitle == nil
                && newNotes == nil && !clearNotes
                && newDueDate == nil && !clearDueDate
                && newPriority == nil && !clearPriority
                && newListName == nil
        }
    }

    static func parseChanges(from json: [String: Any]) throws -> ParsedChanges {
        // Empty strings (and priority < 0) mean "leave unchanged" — strict mode
        // requires every property in `required`, so the LLM has to provide all
        // of them on every call. The boolean clear_* siblings are the explicit
        // "set this back to empty" signal.
        let titleChange = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let notesChange = (json["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let dueDateChange = (json["due_date"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let priorityRaw = (json["priority"] as? Int).flatMap { $0 < 0 ? nil : $0 }
        let listNameChange = (json["list_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let clearNotes = (json["clear_notes"] as? Bool) ?? false
        let clearDueDate = (json["clear_due_date"] as? Bool) ?? false
        let clearPriority = (json["clear_priority"] as? Bool) ?? false

        if clearNotes, notesChange != nil {
            throw NSError(
                domain: "MTUpdateReminderTool",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "clear_notes cannot be combined with a non-empty notes value.",
                ],
            )
        }
        if clearDueDate, dueDateChange != nil {
            throw NSError(
                domain: "MTUpdateReminderTool",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "clear_due_date cannot be combined with a non-empty due_date value.",
                ],
            )
        }
        if clearPriority, priorityRaw != nil {
            throw NSError(
                domain: "MTUpdateReminderTool",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "clear_priority cannot be combined with a priority >= 0.",
                ],
            )
        }

        if let dueDateChange, ReminderToolsShared.parseISODate(dueDateChange) == nil {
            throw NSError(
                domain: "MTUpdateReminderTool",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: "Invalid due_date format. Use ISO 8601 UTC.",
                ],
            )
        }

        return ParsedChanges(
            newTitle: titleChange,
            newNotes: notesChange,
            clearNotes: clearNotes,
            newDueDate: dueDateChange,
            clearDueDate: clearDueDate,
            newPriority: priorityRaw,
            clearPriority: clearPriority,
            newListName: listNameChange,
        )
    }

    static func summarizeChanges(_ changes: ParsedChanges, currentTitle: String?) -> [String] {
        var lines: [String] = []
        if let newTitle = changes.newTitle {
            lines.append(String(localized: "Title: \(currentTitle ?? "-") → \(newTitle)"))
        }
        if changes.clearNotes {
            lines.append(String(localized: "Notes → \(String(localized: "(cleared)"))"))
        } else if let newNotes = changes.newNotes {
            lines.append(String(localized: "Notes → \(newNotes)"))
        }
        if changes.clearDueDate {
            lines.append(String(localized: "Due → \(String(localized: "(cleared)"))"))
        } else if let newDueDate = changes.newDueDate {
            lines.append(String(localized: "Due → \(newDueDate)"))
        }
        if changes.clearPriority {
            lines.append(String(localized: "Priority → \(String(localized: "(cleared)"))"))
        } else if let newPriority = changes.newPriority {
            lines.append(
                String(localized: "Priority → \(ReminderToolsShared.priorityLabel(newPriority))"),
            )
        }
        if let newListName = changes.newListName {
            lines.append(String(localized: "List → \(newListName)"))
        }
        return lines
    }
}

//
//  MTCompleteReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation

final class MTCompleteReminderTool: ConfigurableModelTool, @unchecked Sendable {
    /// The reminder a call names, and the state it asks for.
    private struct Request {
        let reminderId: String
        let completed: Bool
    }

    var interfaceName: String {
        String(localized: "Complete Reminder")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "complete_reminder",
            description: "Mark a reminder completed, or un-complete it. Get reminder_id from query_reminders first.",
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier from query_reminders.",
                    ],
                    "completed": [
                        "type": "boolean",
                        "description": "true completes, false un-completes.",
                    ],
                ],
                "required": ["reminder_id", "completed"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Complete Reminder",
            explain: "Allows LLM to mark reminders as completed.",
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
            let action = request.completed
                ? String(localized: "Mark as Done")
                : String(localized: "Mark as Not Done")
            let title = ReminderToolsShared.displayTitle(of: reminder)
            return [action, title].joined(separator: "\n")
        }
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let request = try parse(arguments)
        try await ReminderToolsShared.requireAccess()

        let eventStore = EKEventStore()
        let reminder = try ReminderToolsShared.requireReminder(id: request.reminderId, eventStore: eventStore)

        let title = ReminderToolsShared.displayTitle(of: reminder)
        reminder.isCompleted = request.completed
        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw ModelToolError.failure(
                String(localized: "Failed to update reminder: \(error.localizedDescription)"),
            )
        }

        let message: String = if request.completed {
            String(localized: "Reminder marked completed: \(title)")
        } else {
            String(localized: "Reminder marked uncompleted: \(title)")
        }
        return ModelToolOutput(text: message)
    }

    private func parse(_ arguments: ModelToolArguments) throws -> Request {
        guard let reminderId = arguments.string("reminder_id"), !reminderId.isEmpty else {
            throw ModelToolError.invalidArguments(String(localized: "reminder_id is required."))
        }
        let completed = arguments["completed"] as? Bool ?? true
        return Request(reminderId: reminderId, completed: completed)
    }
}

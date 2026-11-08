//
//  MTDeleteReminderTool.swift
//  FlowDown
//
//  Created by XZB-1248 on 5/10/26.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation

final class MTDeleteReminderTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Delete Reminder")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "delete_reminder",
            description: "Permanently delete a reminder, after the user confirms. Get reminder_id from query_reminders first.",
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier from query_reminders.",
                    ],
                ],
                "required": ["reminder_id"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Delete Reminder",
            explain: "Allows LLM to delete reminders. The user is asked to confirm each deletion.",
            key: "wiki.qaq.ModelTools.DeleteReminderTool.enabled",
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
        guard let reminderId = try? parse(arguments) else { return nil }
        return ReminderToolsShared.withExistingReminder(id: reminderId) { reminder in
            let title = ReminderToolsShared.displayTitle(of: reminder)
            let listName = ReminderToolsShared.displayListName(of: reminder)
            return [
                title,
                String(localized: "List: \(listName)"),
                "",
                String(localized: "This cannot be undone."),
            ].joined(separator: "\n")
        }
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let reminderId = try parse(arguments)
        try await ReminderToolsShared.requireAccess()

        let eventStore = EKEventStore()
        let reminder = try ReminderToolsShared.requireReminder(id: reminderId, eventStore: eventStore)

        let title = ReminderToolsShared.displayTitle(of: reminder)
        do {
            try eventStore.remove(reminder, commit: true)
        } catch {
            throw ModelToolError.failure(
                String(localized: "Failed to delete reminder: \(error.localizedDescription)"),
            )
        }
        return ModelToolOutput(text: String(localized: "Reminder deleted: \(title)"))
    }

    /// The id of the reminder the call names.
    private func parse(_ arguments: ModelToolArguments) throws -> String {
        guard let reminderId = arguments.string("reminder_id"), !reminderId.isEmpty else {
            throw ModelToolError.invalidArguments(String(localized: "reminder_id is required."))
        }
        return reminderId
    }
}

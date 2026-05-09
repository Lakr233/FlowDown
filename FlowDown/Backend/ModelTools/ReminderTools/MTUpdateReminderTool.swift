//
//  MTUpdateReminderTool.swift
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

class MTUpdateReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "update fields of an existing reminder by ID"
    }

    override var interfaceName: String {
        String(localized: "Update Reminder")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "update_reminder",
            description: """
            Update an existing reminder. Use query_reminders first to obtain the reminder_id. Pass empty string (or -1 for priority) to leave a field unchanged. All dates are ISO 8601 UTC.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier of the reminder, from query_reminders.",
                    ],
                    "title": [
                        "type": "string",
                        "description": "New title. Pass empty string to leave unchanged.",
                    ],
                    "notes": [
                        "type": "string",
                        "description": "New notes. Pass empty string to leave unchanged.",
                    ],
                    "due_date": [
                        "type": "string",
                        "description": "New due date in ISO 8601 UTC (yyyy-MM-dd'T'HH:mm:ss'Z'). Pass empty string to leave unchanged.",
                    ],
                    "priority": [
                        "type": "integer",
                        "description": "New priority (0 = none, 1 = high, 5 = medium, 9 = low). Pass -1 to leave unchanged.",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Move to this Reminders list by name. Pass empty string to leave unchanged.",
                    ],
                ],
                "required": ["reminder_id", "title", "notes", "due_date", "priority", "list_name"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Update Reminder",
            explain: "Allows LLM to modify reminders, including marking them as complete.",
            key: "wiki.qaq.ModelTools.UpdateReminderTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let reminderId = json["reminder_id"] as? String, !reminderId.isEmpty
        else {
            throw NSError(
                domain: "MTUpdateReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "reminder_id is required."),
                ],
            )
        }

        // Empty strings (and priority < 0) mean "leave unchanged" — strict mode
        // requires every property in `required`, so the LLM has to provide all
        // of them on every call.
        let titleChange = (json["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let notesChange = (json["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let dueDateChange = (json["due_date"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let priorityRaw = (json["priority"] as? Int).flatMap { $0 < 0 ? nil : $0 }
        let listNameChange = (json["list_name"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        if let dueDateChange, ReminderToolsShared.parseISODate(dueDateChange) == nil {
            throw NSError(
                domain: "MTUpdateReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid due_date format. Use ISO 8601 UTC."),
                ],
            )
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTUpdateReminderTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        return try await updateWithUserInteraction(
            reminderId: reminderId,
            newTitle: titleChange,
            newNotes: notesChange,
            newDueDate: dueDateChange,
            newPriority: priorityRaw,
            newListName: listNameChange,
            controller: viewController,
        )
    }

    @MainActor
    private func updateWithUserInteraction(
        reminderId: String,
        newTitle: String?,
        newNotes: String?,
        newDueDate: String?,
        newPriority: Int?,
        newListName: String?,
        controller: UIViewController,
    ) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            ReminderToolsShared.requestAccess { [weak self] granted in
                Task { @MainActor in
                    guard let self else {
                        cont.resume(returning: String(localized: "Reminders access denied. Please enable Reminders access in Settings."))
                        return
                    }
                    guard granted else {
                        cont.resume(returning: String(localized: "Reminders access denied. Please enable Reminders access in Settings."))
                        return
                    }

                    let eventStore = EKEventStore()
                    guard let reminder = ReminderToolsShared.fetchReminder(id: reminderId, eventStore: eventStore) else {
                        cont.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Reminder with id \(reminderId) not found."),
                        ]))
                        return
                    }

                    self.showConfirmation(
                        reminder: reminder,
                        eventStore: eventStore,
                        newTitle: newTitle,
                        newNotes: newNotes,
                        newDueDate: newDueDate,
                        newPriority: newPriority,
                        newListName: newListName,
                        controller: controller,
                        continuation: cont,
                    )
                }
            }
        }
    }

    @MainActor
    private func showConfirmation(
        reminder: EKReminder,
        eventStore: EKEventStore,
        newTitle: String?,
        newNotes: String?,
        newDueDate: String?,
        newPriority: Int?,
        newListName: String?,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        var changes: [String] = []
        if let newTitle {
            changes.append(String(localized: "Title: \(reminder.title ?? "-") → \(newTitle)"))
        }
        if let newNotes {
            changes.append(String(localized: "Notes → \(newNotes)"))
        }
        if let newDueDate {
            changes.append(String(localized: "Due → \(newDueDate)"))
        }
        if let newPriority {
            changes.append(String(localized: "Priority → \(ReminderToolsShared.priorityLabel(newPriority))"))
        }
        if let newListName {
            changes.append(String(localized: "List → \(newListName)"))
        }

        if changes.isEmpty {
            continuation.resume(returning: String(localized: "No changes specified; reminder left untouched."))
            return
        }

        let title = reminder.title ?? String(localized: "Untitled")
        let body = title + "\n\n" + changes.joined(separator: "\n")
        let alert = AlertViewController(
            title: "Update Reminder",
            message: body,
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled the operation."),
                    ]))
                }
            }
            context.addAction(title: "Update", attribute: .accent) {
                context.dispose {
                    if let newTitle { reminder.title = newTitle }
                    if let newNotes { reminder.notes = newNotes }
                    if let newDueDate, let date = ReminderToolsShared.parseISODate(newDueDate) {
                        reminder.dueDateComponents = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: date,
                        )
                    }
                    if let newPriority {
                        reminder.priority = newPriority
                    }
                    if let newListName,
                       let calendar = ReminderToolsShared.resolveCalendar(named: newListName, eventStore: eventStore)
                    {
                        reminder.calendar = calendar
                    }

                    do {
                        try eventStore.save(reminder, commit: true)
                        continuation.resume(returning: String(localized: "Reminder updated: \(reminder.title ?? "-")"))
                    } catch {
                        continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to update reminder: \(error.localizedDescription)"),
                        ]))
                    }
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
                    NSLocalizedDescriptionKey: String(localized: "Failed to display confirmation dialog."),
                ]))
                return
            }
        }
    }
}

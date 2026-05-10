//
//  MTDeleteReminderTool.swift
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

class MTDeleteReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "delete a reminder by ID"
    }

    override var interfaceName: String {
        String(localized: "Delete Reminder")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "delete_reminder",
            description: """
            Permanently delete a reminder. Use query_reminders first to obtain the reminder_id. This is irreversible; the user is prompted before deletion.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier of the reminder to delete, from query_reminders.",
                    ],
                ],
                "required": ["reminder_id"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Delete Reminder",
            explain: "Allows LLM to delete reminders. The user is asked to confirm each deletion.",
            key: "wiki.qaq.ModelTools.DeleteReminderTool.enabled",
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
                domain: "MTDeleteReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "reminder_id is required."),
                ],
            )
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTDeleteReminderTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        return try await deleteWithUserInteraction(reminderId: reminderId, controller: viewController)
    }

    @MainActor
    private func deleteWithUserInteraction(
        reminderId: String,
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
                    guard let reminder = ReminderToolsShared.fetchReminder(id: reminderId, eventStore: eventStore) else {
                        cont.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Reminder with id \(reminderId) not found."),
                        ]))
                        return
                    }

                    self.showConfirmation(
                        reminder: reminder,
                        eventStore: eventStore,
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
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        let title = reminder.title ?? String(localized: "Untitled")
        let listName = reminder.calendar?.title ?? String(localized: "Reminders")

        let body = title + "\n"
            + String(localized: "List: \(listName)") + "\n\n"
            + String(localized: "This cannot be undone.")
        let alert = AlertViewController(
            title: "Delete Reminder",
            message: body,
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled the operation."),
                    ]))
                }
            }
            context.addAction(title: "Delete", attribute: .accent) {
                context.dispose {
                    do {
                        try eventStore.remove(reminder, commit: true)
                        continuation.resume(returning: String(localized: "Reminder deleted: \(title)"))
                    } catch {
                        continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to delete reminder: \(error.localizedDescription)"),
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

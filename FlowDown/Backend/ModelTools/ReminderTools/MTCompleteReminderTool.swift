//
//  MTCompleteReminderTool.swift
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

class MTCompleteReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "mark a reminder as completed or uncompleted"
    }

    override var interfaceName: String {
        String(localized: "Complete Reminder")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "complete_reminder",
            description: """
            Mark a reminder as completed or un-complete it. Use query_reminders first to obtain the reminder_id.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "reminder_id": [
                        "type": "string",
                        "description": "calendarItemIdentifier of the reminder, from query_reminders.",
                    ],
                    "completed": [
                        "type": "boolean",
                        "description": "true marks the reminder completed; false un-completes it.",
                    ],
                ],
                "required": ["reminder_id", "completed"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Complete Reminder",
            explain: "Allows LLM to mark reminders as completed.",
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
                domain: "MTCompleteReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "reminder_id is required."),
                ],
            )
        }

        let completed = (json["completed"] as? Bool) ?? true

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTCompleteReminderTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        return try await completeWithUserInteraction(
            reminderId: reminderId,
            completed: completed,
            controller: viewController,
        )
    }

    @MainActor
    private func completeWithUserInteraction(
        reminderId: String,
        completed: Bool,
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
                        completed: completed,
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
        completed: Bool,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        let title = reminder.title ?? String(localized: "Untitled")
        let dialogTitle = completed
            ? String(localized: "Mark as Done")
            : String(localized: "Mark as Not Done")
        let actionLabel = completed
            ? String(localized: "Mark Done")
            : String(localized: "Un-complete")

        let alert = AlertViewController(
            title: dialogTitle,
            message: title,
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled the operation."),
                    ]))
                }
            }
            context.addAction(title: actionLabel, attribute: .accent) {
                context.dispose {
                    reminder.isCompleted = completed
                    do {
                        try eventStore.save(reminder, commit: true)
                        let message: String = if completed {
                            String(localized: "Reminder marked completed: \(title)")
                        } else {
                            String(localized: "Reminder marked uncompleted: \(title)")
                        }
                        continuation.resume(returning: message)
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

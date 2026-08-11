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
    override var interfaceName: String {
        String(localized: "Complete Reminder")
    }

    override var definition: ChatRequestBody.Tool {
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
        guard let json = decodeArguments(input),
              let reminderId = json["reminder_id"] as? String, !reminderId.isEmpty
        else {
            throw NSError(
                domain: "MTCompleteReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "reminder_id is required."),
                ],
            )
        }

        let completed = (json["completed"] as? Bool) ?? true

        let viewController = try await anchorController(for: view)

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
        try await ReminderToolsShared.withAuthorization { cont in
            let eventStore = EKEventStore()
            guard let reminder = ReminderToolsShared.fetchReminder(id: reminderId, eventStore: eventStore) else {
                cont.resume(throwing: ModelToolError.failure(String(localized: "Reminder with id \(reminderId) not found.")))
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
                    continuation.resume(throwing: ModelToolError.userCancelled())
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
                        continuation.resume(throwing: ModelToolError.failure(String(localized: "Failed to update reminder: \(error.localizedDescription)")))
                    }
                }
            }
        }

        ModelToolPresentation.present(
            alert,
            on: controller,
            continuation: continuation,
            displayFailure: String(localized: "Failed to display confirmation dialog."),
        )
    }
}

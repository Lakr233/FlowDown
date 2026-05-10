//
//  MTAddReminderTool.swift
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

class MTAddReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "create a new reminder in user's system Reminders"
    }

    override var interfaceName: String {
        String(localized: "Add to Reminders")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "add_reminder",
            description: """
            Creates a new reminder in the user's system Reminders. Provide a title and any optional fields. Convert all dates to ISO 8601 UTC (yyyy-MM-dd'T'HH:mm:ss'Z') yourself; do not ask the user.
            Priority follows EKReminder convention: 0 = no priority, 1 = high, 5 = medium, 9 = low.
            Pass an empty string for optional text fields and an empty string for due_date when not set. Pass 0 for priority when not set. Pass an empty list_name to use the default Reminders list.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Title of the reminder. Required and must be non-empty.",
                    ],
                    "notes": [
                        "type": "string",
                        "description": "Free-form notes for the reminder. Pass empty string for none.",
                    ],
                    "due_date": [
                        "type": "string",
                        "description": "Due date in ISO 8601 UTC (yyyy-MM-dd'T'HH:mm:ss'Z'). Pass empty string for no due date.",
                    ],
                    "priority": [
                        "type": "integer",
                        "description": "EKReminder priority (0 = none, 1 = high, 5 = medium, 9 = low).",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Name of the Reminders list (calendar) to add to. Pass empty string for the default list.",
                    ],
                ],
                "required": ["title", "notes", "due_date", "priority", "list_name"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Add to Reminders",
            explain: "Allows LLM to create reminders in your system Reminders.",
            key: "wiki.qaq.ModelTools.AddReminderTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let title = json["title"] as? String, !title.isEmpty
        else {
            throw NSError(
                domain: "MTAddReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "A non-empty title is required."),
                ],
            )
        }

        let notes = (json["notes"] as? String) ?? ""
        let dueDateString = (json["due_date"] as? String) ?? ""
        let priority = (json["priority"] as? Int) ?? 0
        let listName = (json["list_name"] as? String) ?? ""

        let dueDate: Date? = dueDateString.isEmpty ? nil : ReminderToolsShared.parseISODate(dueDateString)
        if !dueDateString.isEmpty, dueDate == nil {
            throw NSError(
                domain: "MTAddReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid due_date format. Use ISO 8601 UTC."),
                ],
            )
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTAddReminderTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        return try await addWithUserInteraction(
            title: title,
            notes: notes,
            dueDate: dueDate,
            priority: priority,
            listName: listName,
            controller: viewController,
        )
    }

    @MainActor
    private func addWithUserInteraction(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: Int,
        listName: String,
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
                    self.showConfirmation(
                        title: title,
                        notes: notes,
                        dueDate: dueDate,
                        priority: priority,
                        listName: listName,
                        controller: controller,
                        continuation: cont,
                    )
                }
            }
        }
    }

    @MainActor
    private func showConfirmation(
        title: String,
        notes: String,
        dueDate: Date?,
        priority: Int,
        listName: String,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        var lines = [String(localized: "Title: \(title)")]
        if !notes.isEmpty {
            lines.append(String(localized: "Notes: \(notes)"))
        }
        if let dueDate {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            lines.append(String(localized: "Due: \(formatter.string(from: dueDate))"))
        }
        if priority != 0 {
            lines.append(String(localized: "Priority: \(ReminderToolsShared.priorityLabel(priority))"))
        }
        if !listName.isEmpty {
            lines.append(String(localized: "List: \(listName)"))
        }

        let alert = AlertViewController(
            title: "Add to Reminders",
            message: lines.joined(separator: "\n"),
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled the operation."),
                    ]))
                }
            }
            context.addAction(title: "Add", attribute: .accent) {
                context.dispose {
                    let eventStore = EKEventStore()
                    let reminder = EKReminder(eventStore: eventStore)
                    reminder.title = title
                    if !notes.isEmpty { reminder.notes = notes }
                    if let dueDate {
                        reminder.dueDateComponents = Calendar.current.dateComponents(
                            [.year, .month, .day, .hour, .minute],
                            from: dueDate,
                        )
                    }
                    if priority != 0 { reminder.priority = priority }
                    do {
                        reminder.calendar = try ReminderToolsShared.resolveCalendarRequiringName(
                            named: listName,
                            eventStore: eventStore,
                        )
                        try eventStore.save(reminder, commit: true)
                        let id = reminder.calendarItemIdentifier
                        continuation.resume(returning: String(localized: "Reminder added: \(title) [id: \(id)]"))
                    } catch let error as NSError where error.domain == ReminderToolsShared.errorDomain {
                        continuation.resume(throwing: error)
                    } catch {
                        continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to add reminder: \(error.localizedDescription)"),
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

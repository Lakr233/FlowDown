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
    override var interfaceName: String {
        String(localized: "Add to Reminders")
    }

    override var definition: ChatRequestBody.Tool {
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
        guard let json = decodeArguments(input),
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

        let viewController = try await anchorController(for: view)

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
        try await ReminderToolsShared.withAuthorization { cont in
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
                    continuation.resume(throwing: ModelToolError.userCancelled())
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
                        continuation.resume(throwing: ModelToolError.failure(String(localized: "Failed to add reminder: \(error.localizedDescription)")))
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

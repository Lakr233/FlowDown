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
  override var interfaceName: String {
    String(localized: "Update Reminder")
  }

  override var definition: ChatRequestBody.Tool {
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
    guard let json = decodeArguments(input),
      let reminderId = json["reminder_id"] as? String, !reminderId.isEmpty
    else {
      throw NSError(
        domain: "MTUpdateReminderTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: String(localized: "reminder_id is required.")
        ],
      )
    }

    let parsed = try Self.parseChanges(from: json)

    let viewController = try await anchorController(for: view)

    return try await updateWithUserInteraction(
      reminderId: reminderId,
      changes: parsed,
      controller: viewController,
    )
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
        domain: "MTUpdateReminderTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: "clear_notes cannot be combined with a non-empty notes value."
        ],
      )
    }
    if clearDueDate, dueDateChange != nil {
      throw NSError(
        domain: "MTUpdateReminderTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey:
            "clear_due_date cannot be combined with a non-empty due_date value."
        ],
      )
    }
    if clearPriority, priorityRaw != nil {
      throw NSError(
        domain: "MTUpdateReminderTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: "clear_priority cannot be combined with a priority >= 0."
        ],
      )
    }

    if let dueDateChange, ReminderToolsShared.parseISODate(dueDateChange) == nil {
      throw NSError(
        domain: "MTUpdateReminderTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: "Invalid due_date format. Use ISO 8601 UTC."
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

  @MainActor
  private func updateWithUserInteraction(
    reminderId: String,
    changes: ParsedChanges,
    controller: UIViewController,
  ) async throws -> String {
    try await ReminderToolsShared.withAuthorization { cont in
      let eventStore = EKEventStore()
      guard
        let reminder = ReminderToolsShared.fetchReminder(id: reminderId, eventStore: eventStore)
      else {
        cont.resume(
          throwing: ModelToolError.failure(String(localized: "Reminder with id \(reminderId) not found.")))
        return
      }

      self.showConfirmation(
        reminder: reminder,
        eventStore: eventStore,
        changes: changes,
        controller: controller,
        continuation: cont,
      )
    }
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
        String(localized: "Priority → \(ReminderToolsShared.priorityLabel(newPriority))"))
    }
    if let newListName = changes.newListName {
      lines.append(String(localized: "List → \(newListName)"))
    }
    return lines
  }

  @MainActor
  private func showConfirmation(
    reminder: EKReminder,
    eventStore: EKEventStore,
    changes: ParsedChanges,
    controller: UIViewController,
    continuation: CheckedContinuation<String, any Swift.Error>,
  ) {
    let summary = Self.summarizeChanges(changes, currentTitle: reminder.title)

    if summary.isEmpty {
      continuation.resume(
        returning: String(localized: "No changes specified; reminder left untouched."))
      return
    }

    let title = reminder.title ?? String(localized: "Untitled")
    let body = title + "\n\n" + summary.joined(separator: "\n")
    let alert = AlertViewController(
      title: "Update Reminder",
      message: body,
    ) { context in
      context.addAction(title: "Cancel") {
        context.dispose {
          continuation.resume(
            throwing: ModelToolError.userCancelled())
        }
      }
      context.addAction(title: "Update", attribute: .accent) {
        context.dispose {
          if let newTitle = changes.newTitle { reminder.title = newTitle }
          if changes.clearNotes {
            reminder.notes = nil
          } else if let newNotes = changes.newNotes {
            reminder.notes = newNotes
          }
          if changes.clearDueDate {
            reminder.dueDateComponents = nil
          } else if let newDueDate = changes.newDueDate,
            let date = ReminderToolsShared.parseISODate(newDueDate)
          {
            reminder.dueDateComponents = Calendar.current.dateComponents(
              [.year, .month, .day, .hour, .minute],
              from: date,
            )
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
            continuation.resume(
              returning: String(localized: "Reminder updated: \(reminder.title ?? "-")"))
          } catch let error as NSError where error.domain == ReminderToolsShared.errorDomain {
            continuation.resume(throwing: error)
          } catch {
            continuation.resume(
              throwing: ModelToolError.failure(String(localized: "Failed to update reminder: \(error.localizedDescription)")))
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

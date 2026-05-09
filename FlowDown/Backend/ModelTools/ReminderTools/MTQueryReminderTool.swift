//
//  MTQueryReminderTool.swift
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

class MTQueryReminderTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "query reminders from user's system Reminders"
    }

    override var interfaceName: String {
        String(localized: "Query Reminders")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "query_reminders",
            description: """
            Query reminders from the user's system Reminders. Filter by completion status and optionally by due-date range and Reminders list name. Reminders without a due date are included regardless of date range.
            Date range cannot exceed 365 days. All dates are ISO 8601 UTC.
            Pass empty strings for any optional filter you don't want applied.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "status": [
                        "type": "string",
                        "enum": ["incomplete", "completed", "all"],
                        "description": "Which reminders to return.",
                    ],
                    "start_date": [
                        "type": "string",
                        "description": "Lower bound of due-date filter in ISO 8601 UTC. Pass empty string to skip the lower bound.",
                    ],
                    "end_date": [
                        "type": "string",
                        "description": "Upper bound of due-date filter in ISO 8601 UTC. Pass empty string to skip the upper bound.",
                    ],
                    "list_name": [
                        "type": "string",
                        "description": "Restrict to a single Reminders list by name. Pass empty string to query all lists.",
                    ],
                ],
                "required": ["status", "start_date", "end_date", "list_name"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "checklist",
            title: "Query Reminders",
            explain: "Allows LLM to read your reminders.",
            key: "wiki.qaq.ModelTools.QueryReminderTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw NSError(
                domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid input parameters"),
                ],
            )
        }

        let status = (json["status"] as? String) ?? "incomplete"
        let startDateString = (json["start_date"] as? String) ?? ""
        let endDateString = (json["end_date"] as? String) ?? ""
        let listName = (json["list_name"] as? String) ?? ""

        let startDate = startDateString.isEmpty ? nil : ReminderToolsShared.parseISODate(startDateString)
        let endDate = endDateString.isEmpty ? nil : ReminderToolsShared.parseISODate(endDateString)

        if !startDateString.isEmpty, startDate == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Invalid start_date format. Use ISO 8601 UTC."),
            ])
        }
        if !endDateString.isEmpty, endDate == nil {
            throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Invalid end_date format. Use ISO 8601 UTC."),
            ])
        }

        if let startDate, let endDate {
            let days = Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0
            if days > 365 {
                throw NSError(domain: "MTQueryReminderTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Date range cannot exceed 365 days"),
                ])
            }
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(domain: "MTQueryReminderTool", code: 500, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
            ])
        }

        return try await queryWithUserInteraction(
            status: status,
            startDate: startDate,
            endDate: endDate,
            listName: listName,
            controller: viewController,
        )
    }

    @MainActor
    private func queryWithUserInteraction(
        status: String,
        startDate: Date?,
        endDate: Date?,
        listName: String,
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

                    self.fetchReminders(
                        status: status,
                        startDate: startDate,
                        endDate: endDate,
                        listName: listName,
                    ) { result in
                        // EventKit's fetchReminders callback fires on a background
                        // queue; hop back to the main actor before touching UI.
                        Task { @MainActor [weak self] in
                            guard let self else {
                                cont.resume(returning: result)
                                return
                            }
                            self.showResults(result: result, controller: controller, continuation: cont)
                        }
                    }
                }
            }
        }
    }

    private func fetchReminders(
        status: String,
        startDate: Date?,
        endDate: Date?,
        listName: String,
        completion: @escaping (String) -> Void,
    ) {
        let eventStore = EKEventStore()

        let calendars: [EKCalendar]?
        if !listName.isEmpty {
            let trimmed = listName.trimmingCharacters(in: .whitespacesAndNewlines)
            let match = eventStore.calendars(for: .reminder)
                .first { $0.title.caseInsensitiveCompare(trimmed) == .orderedSame }
            if let match {
                calendars = [match]
            } else {
                completion(String(localized: "No Reminders list named \"\(listName)\" found."))
                return
            }
        } else {
            calendars = nil
        }

        let predicate: NSPredicate
        switch status {
        case "completed":
            predicate = eventStore.predicateForCompletedReminders(
                withCompletionDateStarting: startDate,
                ending: endDate,
                calendars: calendars,
            )
        case "all":
            predicate = eventStore.predicateForReminders(in: calendars)
        default:
            predicate = eventStore.predicateForIncompleteReminders(
                withDueDateStarting: startDate,
                ending: endDate,
                calendars: calendars,
            )
        }

        eventStore.fetchReminders(matching: predicate) { reminders in
            let list = reminders ?? []
            let filtered: [EKReminder]
            if status == "all", let startDate, let endDate {
                filtered = list.filter { reminder in
                    guard let components = reminder.dueDateComponents,
                          let date = Calendar.current.date(from: components)
                    else { return true }
                    return date >= startDate && date <= endDate
                }
            } else {
                filtered = list
            }
            completion(ReminderToolsShared.formatReminders(filtered))
        }
    }

    @MainActor
    private func showResults(
        result: String,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        let preview = formatPreview(result)

        let alert = AlertViewController(
            title: "Reminders",
            message: preview,
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled sharing reminders."),
                    ]))
                }
            }
            context.addAction(title: "Share", attribute: .accent) {
                context.dispose {
                    continuation.resume(returning: result)
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
                    NSLocalizedDescriptionKey: String(localized: "Failed to display results dialog."),
                ]))
                return
            }
        }
    }

    private func formatPreview(_ markdown: String) -> String {
        var displayLines: [String] = []
        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false)

        var lineCount = 0
        var truncated = false
        for line in lines {
            lineCount += 1
            if lineCount > 8 {
                truncated = true
                break
            }

            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("# ") {
                let title = String(trimmed.dropFirst(2))
                displayLines.append(title)
                displayLines.append(String(repeating: "-", count: title.count))
            } else if trimmed.hasPrefix("- ") {
                var line = String(trimmed.dropFirst(2))
                if let idRange = line.range(of: " [id: ") {
                    line = String(line[..<idRange.lowerBound])
                }
                displayLines.append("• " + line)
            } else if !trimmed.isEmpty {
                displayLines.append(trimmed)
            }
        }

        if truncated {
            displayLines.append("\n... \(String(localized: "More reminders available"))")
        }

        return displayLines.joined(separator: "\n")
    }
}

//
//  AddCalendarTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation
import UIKit

class MTAddCalendarTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "add event to user's default system calendar"
    }

    override var interfaceName: String {
        String(localized: "Add to Calendar")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "add_calendar_event",
            description: """
            Adds a new event to the user's calendar with the provided ICS file content. The ICS file should contain event details such as date, time, and description. Please convert values from user's input to ICS format. Don't ask user to do that.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "ics_file": [
                        "type": "string",
                        "description": """
                        The plain text content of the ICS file to import, which must be a valid ICS format (iCalendar).
                        ICS file must match pattern: BEGIN:VEVENT.*END:VEVENT.
                        ICS file should respect users current date and locale.
                        ICS file must have: SUMMARY, DTSTART, DTEND.
                        ICS date format: yyyyMMdd'T'HHmmss'Z' which is on UTC timezone. Please convert to UTC before sending.
                        """,
                    ],
                ],
                "required": ["ics_file"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "calendar",
            title: "Add to Calendar",
            explain: "Allows LLM to save events to your calendar.",
            key: "wiki.qaq.ModelTools.AddCalendarTool.enabled",
            defaultValue: true,
            annotation: .boolean,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let icsContent = json["ics_file"] as? String
        else {
            throw NSError(
                domain: "MTAddCalendarTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid ICS file content"),
                ],
            )
        }

        var eventName = String(localized: "Event")
        if let summaryRange = icsContent.range(of: "SUMMARY:") {
            let startIndex = summaryRange.upperBound
            if let endIndex = icsContent[startIndex...].firstIndex(where: { $0.isNewline }) {
                eventName = String(icsContent[startIndex ..< endIndex])
            }
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTAddCalendarTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        let result = try await addWithUserInteractions(name: eventName, icsFile: icsContent, controller: viewController)
        return result
    }

    @MainActor
    func addWithUserInteractions(name: String, icsFile: String, controller: UIViewController) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let eventStore = EKEventStore()

            let handleAuthResult: (Bool) -> Void = { granted in
                Task { @MainActor [weak self] in
                    guard let self else {
                        cont.resume(returning: String(localized: "Calendar access denied. Please enable calendar access in Settings."))
                        return
                    }
                    if granted {
                        showAddEventConfirmation(name: name, icsFile: icsFile, controller: controller, continuation: cont)
                    } else {
                        cont.resume(returning: String(localized: "Calendar access denied. Please enable calendar access in Settings."))
                    }
                }
            }

            if #available(iOS 17, macCatalyst 17, *) {
                eventStore.requestFullAccessToEvents { granted, _ in
                    handleAuthResult(granted)
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, _ in
                    handleAuthResult(granted)
                }
            }
        }
    }

    @MainActor
    private func showAddEventConfirmation(
        name _: String,
        icsFile: String,
        controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
    ) {
        // 首先解析ICS内容获取更多信息
        let eventStore = EKEventStore()
        guard let event = parseICSContent(icsFile, eventStore: eventStore) else {
            continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Failed to parse calendar event details."),
            ]))
            return
        }

        // 格式化开始和结束时间
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var eventDetails = [
            String(localized: "Event: \(event.title ?? String(localized: "Untitled Event"))"),
            "",
        ]

        if let startDate = event.startDate {
            eventDetails += [String(localized: "Start: \(dateFormatter.string(from: startDate))")]
        }

        if let endDate = event.endDate {
            eventDetails += [String(localized: "End: \(dateFormatter.string(from: endDate))")]
        }

        if let location = event.location, !location.isEmpty {
            eventDetails += [String(localized: "Location: \(location)")]
        }

        let alert = AlertViewController(
            title: "Add To Calendar",
            message: "\(eventDetails.joined(separator: "\n"))",
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
                    self.importICSToCalendar(icsContent: icsFile) { success, error in
                        if success {
                            continuation.resume(returning: String(localized: "Event added to calendar."))
                        } else {
                            continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                                NSLocalizedDescriptionKey: String(localized: "Failed to add event: \(error?.localizedDescription ?? "Unknown error")"),
                            ]))
                        }
                    }
                }
            }
        }

        // Check if controller already has a presented view controller
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

    private func importICSToCalendar(icsContent: String, completion: @escaping (Bool, (any Swift.Error)?) -> Void) {
        let eventStore = EKEventStore()

        let dir = disposableResourcesDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)

        let fileURL = dir.appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("ics")

        do {
            try icsContent.write(to: fileURL, atomically: true, encoding: .utf8)

            do {
                let icsData = try Data(contentsOf: fileURL)
                let icsString = String(data: icsData, encoding: .utf8) ?? ""

                guard let event = parseICSContent(icsString, eventStore: eventStore) else {
                    completion(false, NSError(
                        domain: "MTAddCalendarTool", code: 2, userInfo: [
                            NSLocalizedDescriptionKey: String(localized: "Failed to parse ICS content"),
                        ],
                    ))
                    return
                }

                try eventStore.save(event, span: .thisEvent)
                completion(true, nil)
            } catch {
                completion(false, error)
            }
        } catch {
            completion(false, error)
        }
    }

    private func parseICSContent(_ content: String, eventStore: EKEventStore) -> EKEvent? {
        let event = EKEvent(eventStore: eventStore)

        if let summaryRange = content.range(of: "SUMMARY:") {
            let startIndex = summaryRange.upperBound
            if let endIndex = content[startIndex...].firstIndex(where: { $0.isNewline }) {
                event.title = String(content[startIndex ..< endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        } else {
            event.title = "Event"
        }

        if let descriptionRange = content.range(of: "DESCRIPTION:") {
            let startIndex = descriptionRange.upperBound
            if let endIndex = content[startIndex...].firstIndex(where: { $0.isNewline }) {
                event.notes = String(content[startIndex ..< endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let locationRange = content.range(of: "LOCATION:") {
            let startIndex = locationRange.upperBound
            if let endIndex = content[startIndex...].firstIndex(where: { $0.isNewline }) {
                event.location = String(content[startIndex ..< endIndex])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if let dtStartRange = content.range(of: "DTSTART:") {
            let startIndex = dtStartRange.upperBound
            if let endIndex = content[startIndex...].firstIndex(where: { $0.isNewline }) {
                let dateString = String(content[startIndex ..< endIndex])
                event.startDate = parseICSDate(dateString)
            }
        }

        if let dtEndRange = content.range(of: "DTEND:") {
            let startIndex = dtEndRange.upperBound
            if let endIndex = content[startIndex...].firstIndex(where: { $0.isNewline }) {
                let dateString = String(content[startIndex ..< endIndex])
                event.endDate = parseICSDate(dateString)
            }
        }

        event.calendar = eventStore.defaultCalendarForNewEvents

        return event
    }

    private func parseICSDate(_ dateString: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        formatter.timeZone = TimeZone(abbreviation: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")

        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.dateFormat = "yyyyMMddHHmmss"
        if let date = formatter.date(from: dateString) {
            return date
        }

        formatter.dateFormat = "yyyyMMdd"
        if let date = formatter.date(from: dateString) {
            return date
        }

        return nil
    }
}

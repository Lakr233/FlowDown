//
//  AddCalendarTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation
import iCalendarParser

final class MTAddCalendarTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Add to Calendar")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "add_calendar_event",
            description:
            "Add an event to the user's calendar from ICS content. Convert the user's wording into ICS yourself; never ask them for it.",
            parameters: [
                "type": "object",
                "properties": [
                    "ics_file": [
                        "type": "string",
                        "description": """
                        iCalendar text containing BEGIN:VEVENT...END:VEVENT with SUMMARY, DTSTART and DTEND.
                        Dates use yyyyMMdd'T'HHmmss'Z' (UTC); convert from the user's date and locale first.
                        """,
                    ],
                ],
                "required": ["ics_file"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "calendar",
            title: "Add to Calendar",
            explain: "Allows LLM to save events to your calendar.",
            key: "wiki.qaq.ModelTools.AddCalendarTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var access: ModelToolAccess {
        .privateData
    }

    var group: ModelToolGroup? {
        .calendar
    }

    func approvalSummary(for arguments: ModelToolArguments) async -> String? {
        guard let icsContent = try? parse(arguments),
              let event = parseICSContent(icsContent, eventStore: EKEventStore())
        else { return nil }
        return eventDetails(for: event).joined(separator: "\n")
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let icsContent = try parse(arguments)

        guard await CalendarToolsShared.requestAccess().granted else {
            return ModelToolOutput(
                text: String(localized: "Calendar access denied. Please enable calendar access in Settings."),
            )
        }

        let eventStore = EKEventStore()
        guard let event = parseICSContent(icsContent, eventStore: eventStore) else {
            throw ModelToolError.failure(String(localized: "Failed to parse calendar event details."))
        }

        do {
            try eventStore.save(event, span: .thisEvent)
        } catch {
            throw ModelToolError.failure(
                String(localized: "Failed to add event: \(error.localizedDescription)"),
            )
        }
        return ModelToolOutput(text: String(localized: "Event added to calendar."))
    }

    /// The ICS text the call carries.
    private func parse(_ arguments: ModelToolArguments) throws -> String {
        guard let icsContent = arguments.string("ics_file") else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid ICS file content"))
        }
        return icsContent
    }

    /// The lines that describe `event` on the approval card.
    private func eventDetails(for event: EKEvent) -> [String] {
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short

        var lines = [
            String(localized: "Event: \(event.title ?? String(localized: "Untitled Event"))"),
        ]

        if let startDate = event.startDate {
            lines += [String(localized: "Start: \(dateFormatter.string(from: startDate))")]
        }

        if let endDate = event.endDate {
            lines += [String(localized: "End: \(dateFormatter.string(from: endDate))")]
        }

        if let location = event.location, !location.isEmpty {
            lines += [String(localized: "Location: \(location)")]
        }

        return lines
    }

    func parseICSContent(_ content: String, eventStore: EKEventStore) -> EKEvent? {
        let normalized = normalizeICSToCRLF(content)
        let parser = ICParser()
        // ICParser rejects input without a valid PRODID, which the tool schema never
        // asks for; retry with one so a bare VEVENT still parses.
        let calendar = parser.calendar(from: normalized)
            ?? parser.calendar(from: "PRODID:-//FlowDown//EN\r\n" + normalized)
        guard let icEvent = calendar?.events.first else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.title = icEvent.summary.map(decodeICSText) ?? "Event"
        event.notes = icEvent.description.map(decodeICSText)
        event.location = icEvent.location.map(decodeICSText)
        event.startDate = icEvent.dtStart?.date
        event.endDate = icEvent.dtEnd?.date
        event.calendar = eventStore.defaultCalendarForNewEvents

        return event
    }

    /// Normalizes line endings to CRLF and strips folded continuation lines
    /// so that ICParser can handle both strict and loose ICS input.
    private func normalizeICSToCRLF(_ content: String) -> String {
        // Splitting CRLF on `.newlines` leaves an empty line between CR and LF, and a
        // folded continuation would join that instead of its property.
        let lines = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        var result: [String] = []
        for line in lines {
            if line.first == " " || line.first == "\t", !result.isEmpty {
                result[result.count - 1] += String(line.dropFirst())
            } else {
                result.append(line)
            }
        }
        return result.joined(separator: "\r\n")
    }

    /// Decodes iCalendar text-value escapes per RFC 5545 §3.3.11.
    private func decodeICSText(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            let char = value[index]
            let nextIndex = value.index(after: index)
            if char == "\\", nextIndex < value.endIndex {
                let next = value[nextIndex]
                switch next {
                case "n", "N":
                    result += "\n"
                case "\\", ";", ",":
                    result.append(next)
                default:
                    result += String(char)
                    result += String(next)
                }
                index = value.index(after: nextIndex)
            } else {
                result += String(char)
                index = nextIndex
            }
        }
        return result
    }
}

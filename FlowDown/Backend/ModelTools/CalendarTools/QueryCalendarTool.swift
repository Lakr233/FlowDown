//
//  QueryCalendarTool.swift
//  FlowDown
//
//  Created on 2/28/25.
//

import ChatClientKit
import ConfigurableKit
import CoreGraphics
import EventKit
import Foundation

final class MTQueryCalendarTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Query Calendar")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "query_calendar_events",
            description: """
            Query the user's calendars for a date or range of up to 7 days. Results come back in the user's local time.
            Convert the user's wording into the date format yourself.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": "Start date as the user's local calendar date, ISO 8601 (YYYY-MM-DD).",
                    ],
                    "end_date": [
                        "type": "string",
                        "description": "End date as the user's local calendar date, ISO 8601 (YYYY-MM-DD). Pass an empty string to query only the start date. Max 7 days.",
                    ],
                    "include_all_day_events": [
                        "type": "boolean",
                        "description": "Include all-day events.",
                    ],
                ],
                "required": ["start_date", "include_all_day_events", "end_date"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "calendar",
            title: "Query Calendar",
            explain: "Allows LLM to read your calendar events.",
            key: "wiki.qaq.ModelTools.QueryCalendarTool.enabled",
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

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let json = arguments.object,
              let startDateString = json["start_date"] as? String
        else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid input parameters"))
        }

        let endDateString = json["end_date"] as? String
        let includeAllDayEvents = json["include_all_day_events"] as? Bool ?? true

        let (startDate, endDate) = try Self.queryWindow(
            start: startDateString,
            end: endDateString,
        )

        let access = await CalendarToolsShared.requestAccess()
        guard access.granted else {
            let errorMessage = access.error?.localizedDescription ?? "Unknown error"
            return ModelToolOutput(
                text: String(localized: "Calendar access denied: \(errorMessage). Please enable calendar access in Settings."),
            )
        }

        let result = fetchCalendarEvents(
            startDate: startDate,
            endDate: endDate,
            includeAllDayEvents: includeAllDayEvents,
        )
        return ModelToolOutput(text: result)
    }

    /// Turns the model's `YYYY-MM-DD` bounds into a search window of whole
    /// local days on `calendar`, ending at the midnight after the end date.
    /// An empty or unparsable end date queries the start date alone.
    static func queryWindow(
        start startDateString: String,
        end endDateString: String?,
        calendar: Calendar = .current,
    ) throws -> (start: Date, end: Date) {
        // The dates name the user's calendar days, so read them in the user's
        // time zone; ISO8601DateFormatter would otherwise parse them as GMT.
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]
        dateFormatter.timeZone = calendar.timeZone

        guard let startDate = dateFormatter.date(from: startDateString) else {
            throw NSError(
                domain: "MTQueryCalendarTool",
                code: 400,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid start date format. Use YYYY-MM-DD."),
                ],
            )
        }

        var endDate: Date
        if let endDateStr = endDateString, let date = dateFormatter.date(from: endDateStr) {
            endDate = date

            // Add one day to end date to include the entire end day (until midnight)
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate

            // Verify date range doesn't exceed 7 days
            let components = calendar.dateComponents([.day], from: startDate, to: endDate)
            if let days = components.day, days > 7 {
                throw NSError(
                    domain: "MTQueryCalendarTool",
                    code: 400,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Date range cannot exceed 7 days"),
                    ],
                )
            }
        } else {
            // If no end date, set to end of start date
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }

        return (startDate, endDate)
    }

    /// The events in the window as Markdown, grouped by day.
    private func fetchCalendarEvents(
        startDate: Date,
        endDate: Date,
        includeAllDayEvents: Bool,
    ) -> String {
        let eventStore = EKEventStore()

        // Create the predicate to search between the start and end dates
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)

        // Fetch all events matching the predicate
        let events = eventStore.events(matching: predicate)

        if events.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.locale = Locale.current

            let startDateString = dateFormatter.string(from: startDate)
            let endDateString = dateFormatter.string(
                from: Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate,
            )

            if startDateString == endDateString {
                return String(localized: "No events found for \(startDateString).")
            } else {
                return String(localized: "No events found between \(startDateString) and \(endDateString).")
            }
        }

        // Format events
        let filteredEvents = includeAllDayEvents ? events : events.filter { !$0.isAllDay }
        if filteredEvents.isEmpty {
            return String(localized: "No events found for the specified criteria.")
        }

        // Group events by date
        var eventsByDate: [String: [EKEvent]] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full
        dateFormatter.timeStyle = .none
        dateFormatter.locale = Locale.current

        let timeFormatter = DateFormatter()
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        timeFormatter.locale = Locale.current

        for event in filteredEvents {
            guard let startDate = event.startDate else { continue }
            let dateString = dateFormatter.string(from: startDate)

            if eventsByDate[dateString] == nil {
                eventsByDate[dateString] = []
            }

            eventsByDate[dateString]?.append(event)
        }

        // Sort dates and events
        let sortedDates = eventsByDate.keys.sorted { date1, date2 in
            guard let date1Obj = dateFormatter.date(from: date1),
                  let date2Obj = dateFormatter.date(from: date2)
            else {
                return date1 < date2
            }
            return date1Obj < date2Obj
        }

        // Build result string
        var resultBuilder = [String]()

        for dateString in sortedDates {
            resultBuilder.append("# \(dateString)")
            resultBuilder.append("")

            guard let dateEvents = eventsByDate[dateString] else { continue }
            let sortedEvents = dateEvents.sorted { $0.startDate ?? Date() < $1.startDate ?? Date() }

            for event in sortedEvents {
                let calendar = event.calendar
                let calendarColor = calendar?.cgColor != nil ? colorName(from: calendar!.cgColor) : "Default"

                var eventString = ""

                if event.isAllDay {
                    eventString += "- **\(event.title ?? "-")** (\(String(localized: "All day")))"
                } else if let startDate = event.startDate, let endDate = event.endDate {
                    let startTimeStr = timeFormatter.string(from: startDate)
                    let endTimeStr = timeFormatter.string(from: endDate)
                    eventString += "- **\(event.title ?? "-")** (\(startTimeStr) - \(endTimeStr))"
                } else {
                    eventString += "- **\(event.title ?? "-")**"
                }

                eventString += " [\(calendar?.title ?? String(localized: "Calendar")): \(calendarColor)]"

                if let location = event.location, !location.isEmpty {
                    eventString += "\n  📍 \(location)"
                }

                resultBuilder.append(eventString)
                resultBuilder.append("")
            }
        }

        return resultBuilder.joined(separator: "\n")
    }

    private func colorName(from cgColor: CGColor) -> String {
        let colorNames = [
            [1.0, 0.0, 0.0]: "red",
            [0.0, 1.0, 0.0]: "green",
            [0.0, 0.0, 1.0]: "blue",
            [1.0, 1.0, 0.0]: "yellow",
            [1.0, 0.0, 1.0]: "magenta",
            [0.0, 1.0, 1.0]: "cyan",
            [1.0, 0.5, 0.0]: "orange",
            [0.5, 0.0, 0.5]: "purple",
            [0.5, 0.5, 0.5]: "gray",
        ]

        guard let components = cgColor.components, cgColor.numberOfComponents == 4 else {
            return String(localized: "Default")
        }

        let r = round(components[0] * 10) / 10
        let g = round(components[1] * 10) / 10
        let b = round(components[2] * 10) / 10

        for (colorComponents, name) in colorNames {
            if abs(r - colorComponents[0]) < 0.2,
               abs(g - colorComponents[1]) < 0.2,
               abs(b - colorComponents[2]) < 0.2
            {
                return name
            }
        }

        return String(localized: "Custom Tag Color")
    }
}

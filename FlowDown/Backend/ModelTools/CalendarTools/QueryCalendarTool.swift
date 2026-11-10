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
                "required": ["start_date", "end_date", "include_all_day_events"],
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
        guard let startDateString = arguments.string("start_date") else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid input parameters"))
        }

        let endDateString = arguments.string("end_date")
        let includeAllDayEvents = arguments["include_all_day_events"] as? Bool ?? true

        let (startDate, endDate) = try Self.queryWindow(
            start: startDateString,
            end: endDateString,
        )

        let access = await CalendarToolsShared.requestAccess()
        guard access.granted else {
            let errorMessage = access.error?.localizedDescription ?? "Unknown error"
            return ModelToolOutput(
                text: String(
                    localized: "Calendar access denied: \(errorMessage). Please enable calendar access in Settings."
                ),
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
            throw ModelToolError.invalidArguments(String(localized: "Invalid start date format. Use YYYY-MM-DD."))
        }

        let lastDay = endDateString.flatMap { dateFormatter.date(from: $0) } ?? startDate
        let endDate = calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay

        let components = calendar.dateComponents([.day], from: startDate, to: endDate)
        if let days = components.day, days > 7 {
            throw ModelToolError.invalidArguments(String(localized: "Date range cannot exceed 7 days"))
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
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)

        if events.isEmpty {
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium

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

        let filteredEvents = includeAllDayEvents ? events : events.filter { !$0.isAllDay }
        if filteredEvents.isEmpty {
            return String(localized: "No events found for the specified criteria.")
        }

        var eventsByDate: [String: [EKEvent]] = [:]

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .full

        let timeFormatter = DateFormatter()
        timeFormatter.timeStyle = .short

        for event in filteredEvents {
            guard let startDate = event.startDate else { continue }
            let dateString = dateFormatter.string(from: startDate)
            eventsByDate[dateString, default: []].append(event)
        }

        let sortedDates = eventsByDate.keys.sorted { date1, date2 in
            guard let date1Obj = dateFormatter.date(from: date1),
                  let date2Obj = dateFormatter.date(from: date2)
            else {
                return date1 < date2
            }
            return date1Obj < date2Obj
        }

        var resultBuilder = [String]()

        for dateString in sortedDates {
            resultBuilder.append("# \(dateString)")
            resultBuilder.append("")

            let dateEvents = eventsByDate[dateString, default: []]
            let sortedEvents = dateEvents.sorted { $0.startDate < $1.startDate }

            for event in sortedEvents {
                let calendar = event.calendar
                let calendarColor = calendar?.cgColor.map { colorName(from: $0) } ?? "Default"

                var eventString = "- **\(event.title ?? "-")**"

                if event.isAllDay {
                    eventString += " (\(String(localized: "All day")))"
                } else if let startDate = event.startDate, let endDate = event.endDate {
                    let startTimeStr = timeFormatter.string(from: startDate)
                    let endTimeStr = timeFormatter.string(from: endDate)
                    eventString += " (\(startTimeStr) - \(endTimeStr))"
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
        let colorNames: [(components: [Double], name: String)] = [
            ([1.0, 0.0, 0.0], "red"),
            ([0.0, 1.0, 0.0], "green"),
            ([0.0, 0.0, 1.0], "blue"),
            ([1.0, 1.0, 0.0], "yellow"),
            ([1.0, 0.0, 1.0], "magenta"),
            ([0.0, 1.0, 1.0], "cyan"),
            ([1.0, 0.5, 0.0], "orange"),
            ([0.5, 0.0, 0.5], "purple"),
            ([0.5, 0.5, 0.5], "gray"),
        ]

        guard let components = cgColor.components, cgColor.numberOfComponents == 4 else {
            return String(localized: "Default")
        }

        let r = round(components[0] * 10) / 10
        let g = round(components[1] * 10) / 10
        let b = round(components[2] * 10) / 10

        return colorNames.first {
            abs(r - $0.components[0]) < 0.2 && abs(g - $0.components[1]) < 0.2 && abs(b - $0.components[2]) < 0.2
        }?.name ?? String(localized: "Custom Tag Color")
    }
}

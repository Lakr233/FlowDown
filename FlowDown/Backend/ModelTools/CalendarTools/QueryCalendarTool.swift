//
//  QueryCalendarTool.swift
//  FlowDown
//
//  Created on 2/28/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import EventKit
import Foundation
import UIKit

class MTQueryCalendarTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        "query events from user's system calendars"
    }

    override var interfaceName: String {
        String(localized: "Query Calendar")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "query_calendar_events",
            description: """
            Query events from the user's system calendars for a specific date or date range. 
            The date range cannot exceed 7 consecutive days. Results will be returned in the user's local time format.
            You need to convert user provided dates to the required format.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "start_date": [
                        "type": "string",
                        "description": """
                        The start date for the query in ISO 8601 format (YYYY-MM-DD). 
                        This date should be provided in UTC and will be converted to the user's local timezone.
                        """,
                    ],
                    "end_date": [
                        "type": "string",
                        "description": """
                        Optional end date for the query in ISO 8601 format (YYYY-MM-DD). If not provided, 
                        only events on the start date will be returned. The date range cannot exceed 7 days.
                        This date should be provided in UTC and will be converted to the user's local timezone.
                        """,
                    ],
                    "include_all_day_events": [
                        "type": "boolean",
                        "description": "Whether to include all-day events in the results.",
                    ],
                ],
                "required": ["start_date", "include_all_day_events", "end_date"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "calendar",
            title: "Query Calendar",
            explain: "Allows LLM to read your calendar events.",
            key: "wiki.qaq.ModelTools.QueryCalendarTool.enabled",
            defaultValue: true,
            annotation: .boolean,
        )
    }

    override func execute(with input: String, anchorTo view: UIView) async throws -> String {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let startDateString = json["start_date"] as? String
        else {
            throw NSError(
                domain: "MTQueryCalendarTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid input parameters"),
                ],
            )
        }

        let endDateString = json["end_date"] as? String
        let includeAllDayEvents = json["include_all_day_events"] as? Bool ?? true

        // Parse dates
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withFullDate]

        guard let startDate = dateFormatter.date(from: startDateString) else {
            throw NSError(
                domain: "MTQueryCalendarTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid start date format. Use YYYY-MM-DD."),
                ],
            )
        }

        var endDate: Date
        if let endDateStr = endDateString, let date = dateFormatter.date(from: endDateStr) {
            endDate = date

            // Add one day to end date to include the entire end day (until midnight)
            let calendar = Calendar.current
            endDate = calendar.date(byAdding: .day, value: 1, to: endDate) ?? endDate

            // Verify date range doesn't exceed 7 days
            let components = calendar.dateComponents([.day], from: startDate, to: endDate)
            if let days = components.day, days > 7 {
                throw NSError(
                    domain: "MTQueryCalendarTool", code: 400, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Date range cannot exceed 7 days"),
                    ],
                )
            }
        } else {
            // If no end date, set to end of start date
            let calendar = Calendar.current
            endDate = calendar.date(byAdding: .day, value: 1, to: startDate) ?? startDate
        }

        guard let viewController = await view.parentViewController else {
            throw NSError(
                domain: "MTQueryCalendarTool", code: 500, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Could not find view controller"),
                ],
            )
        }

        let result = try await queryWithUserInteraction(
            startDate: startDate,
            endDate: endDate,
            includeAllDayEvents: includeAllDayEvents,
            controller: viewController,
        )

        return result
    }

    @MainActor
    func queryWithUserInteraction(startDate: Date, endDate: Date, includeAllDayEvents: Bool, controller: UIViewController) async throws -> String {
        try await withCheckedThrowingContinuation { cont in
            let eventStore = EKEventStore()

            let handleAuthResult: (Bool, Error?) -> Void = { granted, error in
                Task { @MainActor [weak self] in
                    guard let self else {
                        let errorMessage = error?.localizedDescription ?? "Unknown error"
                        cont.resume(returning: String(localized: "Calendar access denied: \(errorMessage). Please enable calendar access in Settings."))
                        return
                    }

                    guard granted else {
                        let errorMessage = error?.localizedDescription ?? "Unknown error"
                        cont.resume(returning: String(localized: "Calendar access denied: \(errorMessage). Please enable calendar access in Settings."))
                        return
                    }

                    fetchCalendarEvents(
                        startDate: startDate,
                        endDate: endDate,
                        includeAllDayEvents: includeAllDayEvents,
                    ) { result, error in
                        if let error {
                            cont.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                                NSLocalizedDescriptionKey: String(localized: "Failed to query calendar: \(error.localizedDescription)"),
                            ]))
                        } else {
                            self.showQueryResults(result: result, controller: controller, continuation: cont)
                        }
                    }
                }
            }

            if #available(iOS 17, macCatalyst 17, *) {
                eventStore.requestFullAccessToEvents { granted, error in
                    handleAuthResult(granted, error)
                }
            } else {
                eventStore.requestAccess(to: .event) { granted, error in
                    handleAuthResult(granted, error)
                }
            }
        }
    }

    @MainActor
    private func showQueryResults(result: String, controller: UIViewController, continuation: CheckedContinuation<String, any Swift.Error>) {
        // 将Markdown格式的结果转换成更适合展示的纯文本
        let displayText = formatResultForDisplay(result)

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        dateFormatter.locale = Locale.current

        let alert = AlertViewController(
            title: "Calendar Events",
            message: "\(displayText)",
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose {
                    continuation.resume(throwing: NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "User cancelled sharing calendar events."),
                    ]))
                }
            }
            context.addAction(title: "Share", attribute: .accent) {
                context.dispose {
                    // 返回原始的带格式的结果给AI
                    continuation.resume(returning: result)
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
                    NSLocalizedDescriptionKey: String(localized: "Failed to display results dialog."),
                ]))
                return
            }
        }
    }

    // 将Markdown格式的结果转换为更友好的显示格式
    private func formatResultForDisplay(_ markdownResult: String) -> String {
        var displayLines = [String]()
        let lines = markdownResult.split(separator: "\n")

        var lineCount = 0
        var lineLimitExceeded = false

        for line in lines {
            lineCount += 1
            if lineCount > 6 {
                lineLimitExceeded = true
                break
            }

            let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmedLine.hasPrefix("# ") {
                // 日期标题 - 完全去除"# "前缀
                let dateTitle = String(trimmedLine.dropFirst(2))
                displayLines.append(dateTitle)
                displayLines.append(String(repeating: "-", count: dateTitle.count))
            } else if trimmedLine.hasPrefix("- **") {
                // 事件条目 - 将"- **"替换为"• "并删除所有"**"
                var eventLine = trimmedLine
                eventLine = eventLine.replacingOccurrences(of: "- **", with: "• ")
                eventLine = eventLine.replacingOccurrences(of: "**", with: "")
                displayLines.append(eventLine)
            } else if trimmedLine.hasPrefix("  📍") {
                // 位置信息保持原样
                displayLines.append(trimmedLine)
            } else if !trimmedLine.isEmpty {
                // 其他非空行
                displayLines.append(trimmedLine)
            }
        }

        if lineLimitExceeded {
            displayLines.append("\n... \(String(localized: "More events available"))")
        }

        return displayLines.joined(separator: "\n")
    }

    private func fetchCalendarEvents(startDate: Date, endDate: Date, includeAllDayEvents: Bool, completion: @escaping (String, Error?) -> Void) {
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
            let endDateString = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: endDate) ?? endDate)

            if startDateString == endDateString {
                completion(String(localized: "No events found for \(startDateString)."), nil)
            } else {
                completion(String(localized: "No events found between \(startDateString) and \(endDateString)."), nil)
            }
            return
        }

        // Format events
        let filteredEvents = includeAllDayEvents ? events : events.filter { !$0.isAllDay }
        if filteredEvents.isEmpty {
            completion(String(localized: "No events found for the specified criteria."), nil)
            return
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

        completion(resultBuilder.joined(separator: "\n"), nil)
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

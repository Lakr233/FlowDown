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
import iCalendarParser

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
          ]
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
      annotation: .toggle,
    )
  }

  override func execute(with input: String, anchorTo view: UIView) async throws -> String {
    guard let data = input.data(using: .utf8),
      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
      let icsContent = json["ics_file"] as? String
    else {
      throw NSError(
        domain: "MTAddCalendarTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Invalid ICS file content")
        ],
      )
    }

    let eventName = parseICSEventName(icsContent) ?? String(localized: "Event")

    guard let viewController = await view.parentViewController else {
      throw NSError(
        domain: "MTAddCalendarTool", code: 500,
        userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Could not find view controller")
        ],
      )
    }

    return try await addWithUserInteractions(
      name: eventName, icsFile: icsContent, controller: viewController)
  }

  @MainActor
  func addWithUserInteractions(name: String, icsFile: String, controller: UIViewController)
    async throws -> String
  {
    try await withCheckedThrowingContinuation { cont in
      let eventStore = EKEventStore()

      let handleAuthResult: (Bool) -> Void = { granted in
        Task { @MainActor [weak self] in
          guard let self else {
            cont.resume(
              returning: String(
                localized: "Calendar access denied. Please enable calendar access in Settings."))
            return
          }
          if granted {
            showAddEventConfirmation(
              name: name, icsFile: icsFile, controller: controller, continuation: cont)
          } else {
            cont.resume(
              returning: String(
                localized: "Calendar access denied. Please enable calendar access in Settings."))
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
      continuation.resume(
        throwing: NSError(
          domain: String(localized: "Tool"), code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: String(localized: "Failed to parse calendar event details.")
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
          continuation.resume(
            throwing: NSError(
              domain: String(localized: "Tool"), code: -1,
              userInfo: [
                NSLocalizedDescriptionKey: String(localized: "User cancelled the operation.")
              ]))
        }
      }
      context.addAction(title: "Add", attribute: .accent) {
        context.dispose {
          self.importICSToCalendar(icsContent: icsFile) { success, error in
            if success {
              continuation.resume(returning: String(localized: "Event added to calendar."))
            } else {
              continuation.resume(
                throwing: NSError(
                  domain: String(localized: "Tool"), code: -1,
                  userInfo: [
                    NSLocalizedDescriptionKey: String(
                      localized:
                        "Failed to add event: \(error?.localizedDescription ?? "Unknown error")")
                  ]))
            }
          }
        }
      }
    }

    // Check if controller already has a presented view controller
    guard controller.presentedViewController == nil else {
      continuation.resume(
        throwing: NSError(
          domain: String(localized: "Tool"), code: -1,
          userInfo: [
            NSLocalizedDescriptionKey: String(
              localized: "Tool execution failed: authorization dialog is already presented.")
          ]))
      return
    }

    controller.present(alert, animated: true) {
      guard alert.isVisible else {
        continuation.resume(
          throwing: NSError(
            domain: String(localized: "Tool"), code: -1,
            userInfo: [
              NSLocalizedDescriptionKey: String(localized: "Failed to display confirmation dialog.")
            ]))
        return
      }
    }
  }

  private func importICSToCalendar(
    icsContent: String, completion: @escaping (Bool, (any Swift.Error)?) -> Void
  ) {
    let eventStore = EKEventStore()

    guard let event = parseICSContent(icsContent, eventStore: eventStore) else {
      completion(
        false,
        NSError(
          domain: "MTAddCalendarTool", code: 2,
          userInfo: [
            NSLocalizedDescriptionKey: String(localized: "Failed to parse ICS content")
          ],
        ))
      return
    }

    do {
      try eventStore.save(event, span: .thisEvent)
      completion(true, nil)
    } catch {
      completion(false, error)
    }
  }

  private func parseICSContent(_ content: String, eventStore: EKEventStore) -> EKEvent? {
    let normalized = normalizeICSToCRLF(content)
    let parser = ICParser()
    guard let calendar = parser.calendar(from: normalized),
      let icEvent = calendar.events.first
    else { return nil }

    let event = EKEvent(eventStore: eventStore)
    event.title = icEvent.summary.map(decodeICSText) ?? "Event"
    event.notes = icEvent.description.map(decodeICSText)
    event.location = icEvent.location.map(decodeICSText)
    event.startDate = icEvent.dtStart?.date
    event.endDate = icEvent.dtEnd?.date
    event.calendar = eventStore.defaultCalendarForNewEvents

    return event
  }

  private func parseICSEventName(_ content: String) -> String? {
    let normalized = normalizeICSToCRLF(content)
    let parser = ICParser()
    guard let calendar = parser.calendar(from: normalized),
      let summary = calendar.events.first?.summary
    else { return nil }
    return decodeICSText(summary)
  }

  /// Normalizes line endings to CRLF and strips folded continuation lines
  /// so that ICParser can handle both strict and loose ICS input.
  private func normalizeICSToCRLF(_ content: String) -> String {
    let lines = content.components(separatedBy: .newlines)
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
      if char == "\\", value.index(after: index) < value.endIndex {
        let next = value[value.index(after: index)]
        switch next {
        case "n", "N":
          result += "\n"
        case "\\":
          result += "\\"
        case ";":
          result += ";"
        case ",":
          result += ","
        default:
          result += String(char)
          result += String(next)
        }
        index = value.index(after: value.index(after: index))
      } else {
        result += String(char)
        index = value.index(after: index)
      }
    }
    return result
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

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
  override var interfaceName: String {
    String(localized: "Add to Calendar")
  }

  override var definition: ChatRequestBody.Tool {
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
    guard let json = decodeArguments(input),
      let icsContent = json["ics_file"] as? String
    else {
      throw NSError(
        domain: "MTAddCalendarTool", code: 400,
        userInfo: [
          NSLocalizedDescriptionKey: String(localized: "Invalid ICS file content")
        ],
      )
    }

    let viewController = try await anchorController(for: view)

    return try await addWithUserInteractions(icsFile: icsContent, controller: viewController)
  }

  @MainActor
  func addWithUserInteractions(icsFile: String, controller: UIViewController) async throws -> String
  {
    try await withCheckedThrowingContinuation { cont in
      CalendarToolsShared.requestAccess { [weak self] granted, _ in
        Task { @MainActor [weak self] in
          guard let self, granted else {
            cont.resume(
              returning: String(
                localized: "Calendar access denied. Please enable calendar access in Settings."))
            return
          }
          showAddEventConfirmation(
            icsFile: icsFile, controller: controller, continuation: cont)
        }
      }
    }
  }

  @MainActor
  private func showAddEventConfirmation(
    icsFile: String,
    controller: UIViewController,
    continuation: CheckedContinuation<String, any Swift.Error>,
  ) {
    // 首先解析ICS内容获取更多信息
    let eventStore = EKEventStore()
    guard let event = parseICSContent(icsFile, eventStore: eventStore) else {
      continuation.resume(
        throwing: ModelToolError.failure(String(localized: "Failed to parse calendar event details.")))
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
            throwing: ModelToolError.userCancelled())
        }
      }
      context.addAction(title: "Add", attribute: .accent) {
        context.dispose {
          self.importICSToCalendar(icsContent: icsFile) { success, error in
            if success {
              continuation.resume(returning: String(localized: "Event added to calendar."))
            } else {
              continuation.resume(
                throwing: ModelToolError.failure(String(localized: "Failed to add event: \(error?.localizedDescription ?? "Unknown error")")))
            }
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
}

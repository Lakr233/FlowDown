@testable import FlowDown
import Foundation
import Testing

struct ReminderToolsLogicTests {
    // MARK: - parseISODate

    @Test
    func `parseISODate accepts canonical UTC timestamp`() throws {
        let date = try #require(ReminderToolsShared.parseISODate("2026-05-11T12:34:56Z"))
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date,
        )
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 11)
        #expect(components.hour == 12)
        #expect(components.minute == 34)
        #expect(components.second == 56)
    }

    @Test
    func `parseISODate accepts fractional seconds`() throws {
        let date = try #require(ReminderToolsShared.parseISODate("2026-05-11T12:34:56.789Z"))
        let canonical = try #require(ReminderToolsShared.parseISODate("2026-05-11T12:34:56Z"))
        #expect(abs(date.timeIntervalSince(canonical) - 0.789) < 0.001)
    }

    @Test
    func `parseISODate accepts a date-only string`() throws {
        let date = try #require(ReminderToolsShared.parseISODate("2026-05-11"))
        let components = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: date,
        )
        #expect(components.year == 2026)
        #expect(components.month == 5)
        #expect(components.day == 11)
    }

    @Test
    func `parseISODate trims whitespace`() {
        #expect(ReminderToolsShared.parseISODate("  2026-05-11T12:34:56Z  ") != nil)
    }

    @Test
    func `parseISODate rejects empty and malformed inputs`() {
        #expect(ReminderToolsShared.parseISODate("") == nil)
        #expect(ReminderToolsShared.parseISODate("   ") == nil)
        #expect(ReminderToolsShared.parseISODate("not a date") == nil)
        #expect(ReminderToolsShared.parseISODate("2026/05/11") == nil)
        #expect(ReminderToolsShared.parseISODate("11 May 2026") == nil)
    }

    // MARK: - priorityLabel

    @Test
    func `priorityLabel covers EKReminder priority bands`() {
        // 0 = none, 1-4 = high, 5 = medium, 6-9 = low. Outside the documented
        // band falls through to a numeric string, which would surface a model
        // sending out-of-spec values.
        #expect(ReminderToolsShared.priorityLabel(0) == String(localized: "None"))
        #expect(ReminderToolsShared.priorityLabel(1) == String(localized: "High"))
        #expect(ReminderToolsShared.priorityLabel(4) == String(localized: "High"))
        #expect(ReminderToolsShared.priorityLabel(5) == String(localized: "Medium"))
        #expect(ReminderToolsShared.priorityLabel(6) == String(localized: "Low"))
        #expect(ReminderToolsShared.priorityLabel(9) == String(localized: "Low"))
        #expect(ReminderToolsShared.priorityLabel(99) == "99")
        #expect(ReminderToolsShared.priorityLabel(-1) == "-1")
    }

    // MARK: - matchCalendarTitle

    @Test
    func `matchCalendarTitle returns useDefault for empty or whitespace names`() {
        #expect(ReminderToolsShared.matchCalendarTitle("", in: ["Inbox"]) == .useDefault)
        #expect(ReminderToolsShared.matchCalendarTitle("   ", in: ["Inbox"]) == .useDefault)
    }

    @Test
    func `matchCalendarTitle matches case-insensitively and trims whitespace`() {
        let titles = ["Inbox", "Work", "Personal"]
        #expect(ReminderToolsShared.matchCalendarTitle("work", in: titles) == .matched(1))
        #expect(ReminderToolsShared.matchCalendarTitle("WORK", in: titles) == .matched(1))
        #expect(ReminderToolsShared.matchCalendarTitle("  Personal  ", in: titles) == .matched(2))
    }

    @Test
    func `matchCalendarTitle reports notFound for non-empty unknown names`() {
        // The whole point of Fix A: a typo'd list_name must NOT silently fall
        // back to the default list. notFound is the signal callers throw on.
        #expect(ReminderToolsShared.matchCalendarTitle("typo", in: ["Inbox", "Work"]) == .notFound)
        #expect(ReminderToolsShared.matchCalendarTitle("Inbox", in: []) == .notFound)
    }

    @Test
    func `listNotFoundError carries the user-supplied name in its description`() {
        let error = ReminderToolsShared.listNotFoundError("My Made-Up List")
        #expect(error.domain == ReminderToolsShared.errorDomain)
        #expect(error.code == 404)
        let description = error.localizedDescription
        #expect(description.contains("My Made-Up List"))
    }

    @Test
    func `authorizationDeniedError uses the shared error domain`() {
        let error = ReminderToolsShared.authorizationDeniedError()
        #expect(error.domain == ReminderToolsShared.errorDomain)
        #expect(error.code == 403)
        #expect(!error.localizedDescription.isEmpty)
    }

    // MARK: - parseRange (MTQueryReminderTool)

    @Test
    func `parseRange returns empty range when both bounds are blank`() throws {
        let range = try MTQueryReminderTool.parseRange(prefix: "due", startString: "", endString: "")
        #expect(!range.isActive)
        #expect(range.start == nil)
        #expect(range.end == nil)
    }

    @Test
    func `parseRange accepts a single-sided range`() throws {
        let lowerOnly = try MTQueryReminderTool.parseRange(
            prefix: "due", startString: "2026-05-01T00:00:00Z", endString: "",
        )
        #expect(lowerOnly.isActive)
        #expect(lowerOnly.start != nil)
        #expect(lowerOnly.end == nil)

        let upperOnly = try MTQueryReminderTool.parseRange(
            prefix: "due", startString: "", endString: "2026-05-30T00:00:00Z",
        )
        #expect(upperOnly.isActive)
        #expect(upperOnly.start == nil)
        #expect(upperOnly.end != nil)
    }

    @Test
    func `parseRange rejects malformed start string`() {
        #expect(throws: NSError.self) {
            try MTQueryReminderTool.parseRange(
                prefix: "due", startString: "yesterday", endString: "",
            )
        }
    }

    @Test
    func `parseRange rejects malformed end string`() {
        #expect(throws: NSError.self) {
            try MTQueryReminderTool.parseRange(
                prefix: "alert", startString: "", endString: "tomorrow-ish",
            )
        }
    }

    @Test
    func `parseRange rejects start after end`() {
        #expect(throws: NSError.self) {
            try MTQueryReminderTool.parseRange(
                prefix: "due",
                startString: "2026-05-30T00:00:00Z",
                endString: "2026-05-01T00:00:00Z",
            )
        }
    }

    @Test
    func `parseRange rejects ranges longer than 365 days`() {
        #expect(throws: NSError.self) {
            try MTQueryReminderTool.parseRange(
                prefix: "completed",
                startString: "2025-01-01T00:00:00Z",
                endString: "2026-06-01T00:00:00Z",
            )
        }
    }

    @Test
    func `parseRange allows exactly 365 days`() throws {
        let range = try MTQueryReminderTool.parseRange(
            prefix: "completed",
            startString: "2026-01-01T00:00:00Z",
            endString: "2027-01-01T00:00:00Z",
        )
        #expect(range.isActive)
    }

    // MARK: - DateRange.contains

    @Test
    func `DateRange contains reflects bound semantics`() {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let start = formatter.date(from: "2026-05-11T00:00:00Z")!
        let end = formatter.date(from: "2026-05-12T00:00:00Z")!
        let mid = formatter.date(from: "2026-05-11T12:00:00Z")!
        let before = formatter.date(from: "2026-05-10T23:59:59Z")!
        let after = formatter.date(from: "2026-05-12T00:00:01Z")!

        let bounded = MTQueryReminderTool.DateRange(start: start, end: end)
        #expect(bounded.contains(mid))
        #expect(bounded.contains(start))
        #expect(bounded.contains(end))
        #expect(!bounded.contains(before))
        #expect(!bounded.contains(after))

        let unbounded = MTQueryReminderTool.DateRange(start: nil, end: nil)
        #expect(unbounded.contains(mid))
        #expect(unbounded.contains(before))
        #expect(unbounded.contains(after))
        #expect(!unbounded.isActive)
    }

    // MARK: - MTUpdateReminderTool.parseChanges

    @Test
    func `parseChanges treats empty strings as leave-unchanged`() throws {
        let parsed = try MTUpdateReminderTool.parseChanges(from: [
            "reminder_id": "id-1",
            "title": "",
            "notes": "",
            "clear_notes": false,
            "due_date": "",
            "clear_due_date": false,
            "priority": -1,
            "clear_priority": false,
            "list_name": "",
        ])
        #expect(parsed.isEmpty)
        #expect(parsed.newTitle == nil)
        #expect(parsed.newNotes == nil)
        #expect(!parsed.clearNotes)
        #expect(parsed.newDueDate == nil)
        #expect(!parsed.clearDueDate)
        #expect(parsed.newPriority == nil)
        #expect(!parsed.clearPriority)
        #expect(parsed.newListName == nil)
    }

    @Test
    func `parseChanges captures non-empty values verbatim`() throws {
        let parsed = try MTUpdateReminderTool.parseChanges(from: [
            "reminder_id": "id-1",
            "title": "Buy milk",
            "notes": "2L whole",
            "clear_notes": false,
            "due_date": "2026-05-12T09:00:00Z",
            "clear_due_date": false,
            "priority": 5,
            "clear_priority": false,
            "list_name": "Groceries",
        ])
        #expect(parsed.newTitle == "Buy milk")
        #expect(parsed.newNotes == "2L whole")
        #expect(parsed.newDueDate == "2026-05-12T09:00:00Z")
        #expect(parsed.newPriority == 5)
        #expect(parsed.newListName == "Groceries")
        #expect(!parsed.isEmpty)
    }

    @Test
    func `parseChanges accepts the three clear flags independently`() throws {
        let parsed = try MTUpdateReminderTool.parseChanges(from: [
            "reminder_id": "id-1",
            "title": "",
            "notes": "",
            "clear_notes": true,
            "due_date": "",
            "clear_due_date": true,
            "priority": -1,
            "clear_priority": true,
            "list_name": "",
        ])
        #expect(parsed.clearNotes)
        #expect(parsed.clearDueDate)
        #expect(parsed.clearPriority)
        #expect(!parsed.isEmpty)
    }

    @Test
    func `parseChanges rejects clear_notes combined with a non-empty notes value`() {
        #expect(throws: NSError.self) {
            try MTUpdateReminderTool.parseChanges(from: [
                "reminder_id": "id-1",
                "title": "",
                "notes": "Some text",
                "clear_notes": true,
                "due_date": "",
                "clear_due_date": false,
                "priority": -1,
                "clear_priority": false,
                "list_name": "",
            ])
        }
    }

    @Test
    func `parseChanges rejects clear_due_date combined with a non-empty due_date`() {
        #expect(throws: NSError.self) {
            try MTUpdateReminderTool.parseChanges(from: [
                "reminder_id": "id-1",
                "title": "",
                "notes": "",
                "clear_notes": false,
                "due_date": "2026-05-12T09:00:00Z",
                "clear_due_date": true,
                "priority": -1,
                "clear_priority": false,
                "list_name": "",
            ])
        }
    }

    @Test
    func `parseChanges rejects clear_priority combined with a priority >= 0`() {
        #expect(throws: NSError.self) {
            try MTUpdateReminderTool.parseChanges(from: [
                "reminder_id": "id-1",
                "title": "",
                "notes": "",
                "clear_notes": false,
                "due_date": "",
                "clear_due_date": false,
                "priority": 5,
                "clear_priority": true,
                "list_name": "",
            ])
        }
    }

    // MARK: - MTUpdateReminderTool.summarizeChanges

    @Test
    func `summarizeChanges renders cleared sentinels for clear flags`() {
        let parsed = MTUpdateReminderTool.ParsedChanges(
            newTitle: nil,
            newNotes: nil, clearNotes: true,
            newDueDate: nil, clearDueDate: true,
            newPriority: nil, clearPriority: true,
            newListName: nil,
        )
        let lines = MTUpdateReminderTool.summarizeChanges(parsed, currentTitle: "Existing")
        #expect(lines.count == 3)
        let cleared = String(localized: "(cleared)")
        #expect(lines.allSatisfy { $0.contains(cleared) })
        #expect(lines.contains { $0.lowercased().contains("notes") })
        #expect(lines.contains { $0.lowercased().contains("due") })
        #expect(lines.contains { $0.lowercased().contains("priority") })
    }

    @Test
    func `summarizeChanges shows new values for non-cleared fields`() {
        let parsed = MTUpdateReminderTool.ParsedChanges(
            newTitle: "Buy oat milk",
            newNotes: "2L whole", clearNotes: false,
            newDueDate: "2026-05-12T09:00:00Z", clearDueDate: false,
            newPriority: 1, clearPriority: false,
            newListName: "Groceries",
        )
        let lines = MTUpdateReminderTool.summarizeChanges(parsed, currentTitle: "Buy milk")
        #expect(lines.count == 5)
        #expect(lines.contains { $0.contains("Buy milk") && $0.contains("Buy oat milk") })
        #expect(lines.contains { $0.contains("2L whole") })
        #expect(lines.contains { $0.contains("2026-05-12T09:00:00Z") })
        #expect(lines.contains { $0.contains(String(localized: "High")) })
        #expect(lines.contains { $0.contains("Groceries") })
        let cleared = String(localized: "(cleared)")
        #expect(lines.allSatisfy { !$0.contains(cleared) })
    }

    @Test
    func `summarizeChanges returns empty for a no-op update`() {
        let parsed = MTUpdateReminderTool.ParsedChanges(
            newTitle: nil,
            newNotes: nil, clearNotes: false,
            newDueDate: nil, clearDueDate: false,
            newPriority: nil, clearPriority: false,
            newListName: nil,
        )
        #expect(parsed.isEmpty)
        #expect(MTUpdateReminderTool.summarizeChanges(parsed, currentTitle: "Anything").isEmpty)
    }

    @Test
    func `parseChanges rejects malformed due_date`() {
        #expect(throws: NSError.self) {
            try MTUpdateReminderTool.parseChanges(from: [
                "reminder_id": "id-1",
                "title": "",
                "notes": "",
                "clear_notes": false,
                "due_date": "next tuesday",
                "clear_due_date": false,
                "priority": -1,
                "clear_priority": false,
                "list_name": "",
            ])
        }
    }
}

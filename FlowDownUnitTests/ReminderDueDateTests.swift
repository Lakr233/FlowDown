@testable import FlowDown
import Foundation
import Testing

/// A bare `yyyy-MM-dd` from the model names a day on the user's calendar.
/// Reading it as UTC midnight moved the due day for users west of UTC.
struct ReminderDueDateTests {
    @Test
    func dueDateComponents_dateOnlyInNewYork_isAllDayOnThatDay() throws {
        let newYork = try calendar("America/New_York")
        let components = try #require(ReminderToolsShared.dueDateComponents(from: "2026-10-05", calendar: newYork))
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 5)
        #expect(components.hour == nil)
        #expect(components.minute == nil)
    }

    @Test
    func dueDateComponents_dateOnlyInShanghai_isAllDayOnThatDay() throws {
        let shanghai = try calendar("Asia/Shanghai")
        let components = try #require(ReminderToolsShared.dueDateComponents(from: " 2026-10-05 ", calendar: shanghai))
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 5)
        #expect(components.hour == nil)
    }

    @Test
    func dueDateComponents_timestamp_keepsLocalHourAndMinute() throws {
        let newYork = try calendar("America/New_York")
        let components = try #require(ReminderToolsShared.dueDateComponents(from: "2026-10-05T15:30:00Z", calendar: newYork))
        #expect(components.year == 2026)
        #expect(components.month == 10)
        #expect(components.day == 5)
        #expect(components.hour == 11)
        #expect(components.minute == 30)
    }

    @Test
    func dueDateComponents_malformedInput_returnsNil() throws {
        let newYork = try calendar("America/New_York")
        #expect(ReminderToolsShared.dueDateComponents(from: "", calendar: newYork) == nil)
        #expect(ReminderToolsShared.dueDateComponents(from: "next tuesday", calendar: newYork) == nil)
    }

    @Test
    func parseLocalDay_timestamp_returnsNil() throws {
        let newYork = try calendar("America/New_York")
        #expect(ReminderToolsShared.parseLocalDay("2026-10-05T15:30:00Z", calendar: newYork) == nil)
        #expect(ReminderToolsShared.parseLocalDay("2026-10-05T15:30:00.250Z", calendar: newYork) == nil)
        #expect(ReminderToolsShared.parseLocalDay("2026-10-05T15:30:00", calendar: newYork) == nil)
        #expect(ReminderToolsShared.parseLocalDay("2026-10-05T15:30", calendar: newYork) == nil)
        #expect(ReminderToolsShared.parseLocalDay("2026-10-05 15:30", calendar: newYork) == nil)
    }

    @Test
    func dueDateComponents_timestampWithoutOffset_returnsNil() throws {
        // Reading the leading date alone would turn a 15:30 reminder into an
        // all-day one; rejecting it makes the model resend a UTC timestamp.
        let newYork = try calendar("America/New_York")
        #expect(ReminderToolsShared.dueDateComponents(from: "2026-10-05T15:30:00", calendar: newYork) == nil)
        #expect(ReminderToolsShared.dueDateComponents(from: "2026-10-05 15:30", calendar: newYork) == nil)
        #expect(ReminderToolsShared.parseISODate("2026-10-05T15:30:00") == nil)
    }

    @Test
    func parseRange_timestampWithoutOffset_throws() throws {
        let newYork = try calendar("America/New_York")
        #expect(throws: NSError.self) {
            try MTQueryReminderTool.parseRange(
                prefix: "due",
                startString: "",
                endString: "2026-10-05T15:30:00",
                calendar: newYork,
            )
        }
    }

    @Test
    func parseRange_dateOnlyBounds_coverWholeLocalDay() throws {
        let range = try MTQueryReminderTool.parseRange(
            prefix: "due",
            startString: "2026-10-05",
            endString: "2026-10-05",
            calendar: calendar("America/New_York"),
        )
        let localMidnight = try instant("2026-10-05T04:00:00Z")
        let afternoon = try instant("2026-10-05T15:00:00Z")
        let lastMinute = try instant("2026-10-06T03:59:00Z")
        let nextLocalMidnight = try instant("2026-10-06T04:00:00Z")
        let dayBefore = try instant("2026-10-05T03:59:00Z")
        #expect(range.start == localMidnight)
        #expect(range.contains(localMidnight))
        #expect(range.contains(afternoon))
        #expect(range.contains(lastMinute))
        #expect(!range.contains(nextLocalMidnight))
        #expect(!range.contains(dayBefore))
    }

    @Test
    func parseRange_dateOnlyEndBound_includesLaterThatDay() throws {
        let range = try MTQueryReminderTool.parseRange(
            prefix: "due",
            startString: "",
            endString: "2026-10-05",
            calendar: calendar("America/New_York"),
        )
        let afternoon = try instant("2026-10-05T15:00:00Z")
        #expect(range.contains(afternoon))
    }

    @Test
    func parseRange_dateOnlyFullYear_staysWithinLimit() throws {
        let range = try MTQueryReminderTool.parseRange(
            prefix: "due",
            startString: "2026-01-01",
            endString: "2027-01-01",
            calendar: calendar("America/New_York"),
        )
        #expect(range.isActive)
    }
}

private extension ReminderDueDateTests {
    func calendar(_ identifier: String) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: identifier))
        return calendar
    }

    func instant(_ string: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return try #require(formatter.date(from: string))
    }
}

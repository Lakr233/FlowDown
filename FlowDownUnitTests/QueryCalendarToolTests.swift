@testable import FlowDown
import Foundation
import Testing

struct QueryCalendarToolTests {
    @Test
    func queryWindow_singleDayInLosAngeles_coversLocalDay() throws {
        let window = try MTQueryCalendarTool.queryWindow(
            start: "2026-10-02",
            end: "",
            calendar: calendar("America/Los_Angeles"),
        )
        let expectedStart = try instant("2026-10-02T07:00:00Z")
        let expectedEnd = try instant("2026-10-03T07:00:00Z")
        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test
    func queryWindow_singleDayInShanghai_coversLocalDay() throws {
        let window = try MTQueryCalendarTool.queryWindow(
            start: "2026-10-02",
            end: "",
            calendar: calendar("Asia/Shanghai"),
        )
        let expectedStart = try instant("2026-10-01T16:00:00Z")
        let expectedEnd = try instant("2026-10-02T16:00:00Z")
        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test
    func queryWindow_daylightSavingEnd_spansTwentyFiveHours() throws {
        let window = try MTQueryCalendarTool.queryWindow(
            start: "2026-11-01",
            end: "",
            calendar: calendar("America/Los_Angeles"),
        )
        let expectedStart = try instant("2026-11-01T07:00:00Z")
        let expectedEnd = try instant("2026-11-02T08:00:00Z")
        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test
    func queryWindow_dateRange_endsAtMidnightAfterLocalEndDate() throws {
        let window = try MTQueryCalendarTool.queryWindow(
            start: "2026-10-02",
            end: "2026-10-04",
            calendar: calendar("America/Los_Angeles"),
        )
        let expectedStart = try instant("2026-10-02T07:00:00Z")
        let expectedEnd = try instant("2026-10-05T07:00:00Z")
        #expect(window.start == expectedStart)
        #expect(window.end == expectedEnd)
    }

    @Test
    func queryWindow_rangeLongerThanSevenDays_throws() throws {
        let losAngeles = try calendar("America/Los_Angeles")
        #expect(throws: NSError.self) {
            try MTQueryCalendarTool.queryWindow(
                start: "2026-10-01",
                end: "2026-10-08",
                calendar: losAngeles,
            )
        }
    }

    @Test
    func queryWindow_malformedStartDate_throws() throws {
        let losAngeles = try calendar("America/Los_Angeles")
        #expect(throws: NSError.self) {
            try MTQueryCalendarTool.queryWindow(
                start: "Oct 2",
                end: "",
                calendar: losAngeles,
            )
        }
    }
}

private extension QueryCalendarToolTests {
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

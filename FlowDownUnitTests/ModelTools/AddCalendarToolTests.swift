@testable import FlowDown
import EventKit
import Foundation
import Testing

struct AddCalendarToolTests {
    @Test
    func parseICSContent_bareEvent_parses() throws {
        let ics = "BEGIN:VEVENT\nSUMMARY:Lunch\nDTSTART:20261005T040000Z\nDTEND:20261005T050000Z\nEND:VEVENT"
        let event = try #require(parse(ics))
        try expectLunch(event)
    }

    @Test
    func parseICSContent_calendarWithoutProdId_parses() throws {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        BEGIN:VEVENT
        SUMMARY:Lunch
        DTSTART:20261005T040000Z
        DTEND:20261005T050000Z
        END:VEVENT
        END:VCALENDAR
        """
        let event = try #require(parse(ics))
        try expectLunch(event)
    }

    @Test
    func parseICSContent_descriptionMentioningProdId_stillParses() throws {
        let ics = [
            "BEGIN:VEVENT",
            "SUMMARY:Lunch",
            "DESCRIPTION:PRODID:-//Example//EN",
            "DTSTART:20261005T040000Z",
            "DTEND:20261005T050000Z",
            "END:VEVENT",
        ].joined(separator: "\n")
        let event = try #require(parse(ics))
        try expectLunch(event)
        #expect(event.notes == "PRODID:-//Example//EN")
    }

    @Test
    func parseICSContent_crlfWithFoldedDescription_keepsFullText() throws {
        let ics = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//Example//EN",
            "BEGIN:VEVENT",
            "SUMMARY:Lunch",
            "DESCRIPTION:Bring the quarterly",
            "  report and slides",
            "DTSTART:20261005T040000Z",
            "DTEND:20261005T050000Z",
            "END:VEVENT",
            "END:VCALENDAR",
            "",
        ].joined(separator: "\r\n")
        let event = try #require(parse(ics))
        try expectLunch(event)
        #expect(event.notes == "Bring the quarterly report and slides")
    }

    @Test
    func parseICSContent_withoutEvent_returnsNil() {
        #expect(parse("BEGIN:VCALENDAR\nPRODID:-//Example//EN\nEND:VCALENDAR") == nil)
    }
}

private extension AddCalendarToolTests {
    func parse(_ ics: String) -> EKEvent? {
        MTAddCalendarTool().parseICSContent(ics, eventStore: EKEventStore())
    }

    func expectLunch(_ event: EKEvent) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let expectedStart = try #require(formatter.date(from: "2026-10-05T04:00:00Z"))
        let expectedEnd = try #require(formatter.date(from: "2026-10-05T05:00:00Z"))
        #expect(event.title == "Lunch")
        #expect(event.startDate == expectedStart)
        #expect(event.endDate == expectedEnd)
    }
}

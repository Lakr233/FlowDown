//
//  NSAttributedStringSearchTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import Testing
import UIKit

struct NSAttributedStringSearchTests {
    private let key = NSAttributedString.Key("test.highlight")

    @Test
    func highlightedString_lengthChangingLowercase_highlightsOriginalRange() {
        // "İ" lowercases to two scalars, so a lowercased copy is longer.
        for term in ["trip", "TRIP"] {
            let string = NSAttributedString.highlightedString(
                text: "İstanbul trip",
                searchTerm: term,
                highlightAttributes: [key: true],
            )
            #expect(highlightedRanges(in: string) == [NSRange(location: 9, length: 4)])
        }
    }

    @Test
    func highlightedString_matchAfterLengthChangingLowercase_highlightsMatchOnly() {
        let string = NSAttributedString.highlightedString(
            text: "İstanbul trip notes",
            searchTerm: "trip",
            highlightAttributes: [key: true],
        )
        #expect(highlightedRanges(in: string) == [NSRange(location: 9, length: 4)])
    }

    @Test
    func highlightedString_repeatedTerm_highlightsEveryMatch() {
        let string = NSAttributedString.highlightedString(
            text: "Trip trip",
            searchTerm: "trip",
            highlightAttributes: [key: true],
        )
        #expect(highlightedRanges(in: string) == [
            NSRange(location: 0, length: 4),
            NSRange(location: 5, length: 4),
        ])
    }

    private func highlightedRanges(in string: NSAttributedString) -> [NSRange] {
        var ranges: [NSRange] = []
        string.enumerateAttribute(
            key,
            in: NSRange(location: 0, length: string.length),
            options: [],
        ) { value, range, _ in
            if value != nil { ranges.append(range) }
        }
        return ranges
    }
}

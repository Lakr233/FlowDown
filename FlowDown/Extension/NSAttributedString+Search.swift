//
//  NSAttributedString+Search.swift
//  FlowDown
//
//  Created by Alan Ye on 7/8/25.
//

import UIKit

extension NSAttributedString {
    static func highlightedString(
        text: String,
        searchTerm: String,
        baseAttributes: [NSAttributedString.Key: Any] = [:],
        highlightAttributes: [NSAttributedString.Key: Any] = [:],
    ) -> NSAttributedString {
        guard !searchTerm.isEmpty else {
            return NSAttributedString(string: text, attributes: baseAttributes)
        }
        let attributedString = NSMutableAttributedString(string: text, attributes: baseAttributes)

        // Search `text` itself: lowercasing can change the length (such as
        // "İ"), so indices from a lowercased copy may not fit `text`.
        var searchRange = text.startIndex ..< text.endIndex
        while let range = text.range(of: searchTerm, options: [.caseInsensitive], range: searchRange) {
            let nsRange = NSRange(range, in: text)
            attributedString.addAttributes(highlightAttributes, range: nsRange)

            searchRange = range.upperBound ..< text.endIndex
        }

        return attributedString
    }
}

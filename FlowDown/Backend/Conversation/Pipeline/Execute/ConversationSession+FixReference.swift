//
//  ConversationSession+FixReference.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import MarkdownParser
import RegexBuilder
import Storage

private let numberWithHat = Regex {
    ZeroOrMore(.whitespace)
    One("^")
    OneOrMore(.digit)
    ZeroOrMore(.whitespace)
}

private let numberWithOptionalHat = Regex {
    ZeroOrMore(.whitespace)
    Optionally("^")
    OneOrMore(.digit)
    ZeroOrMore(.whitespace)
}

private let regex = Regex {
    "["

    Capture {
        numberWithHat
        ZeroOrMore {
            ","
            numberWithOptionalHat
        }
    }

    "]"

    NegativeLookahead {
        "("
        ZeroOrMore(.any)
        ")"
    }

    Anchor.wordBoundary
}

private let prevent: [MarkdownNodeType] = [
    .blockquote,
    .codeBlock,
    .htmlBlock,
    .customBlock,
    .thematicBreak,
    .code,
    .html,
    .customInline,
    .emphasis,
    .strong,
    .link,
    .image,
    .strikethrough,
]

extension ConversationSession {
    func fixWebReferenceIfPossible(
        in content: String,
        with contentLink: [Int: String],
    ) -> String {
        if content.isEmpty || contentLink.isEmpty { return content }

        var content = content
        let map = MarkdownParser().parseBlockRange(content)

        var duplicationTerminator: String.Index? = nil

        let reverseOrderedMatches = content.matches(of: regex)
            .sorted { $0.range.lowerBound > $1.range.lowerBound }
            .filter { input in
                if let duplicationTerminator {
                    guard input.range.lowerBound < duplicationTerminator,
                          input.range.upperBound < duplicationTerminator
                    else {
                        assertionFailure()
                        return false
                    }
                    return true
                }
                duplicationTerminator = input.range.lowerBound
                return true
            }

        for match in reverseOrderedMatches {
            let source = match.output.1
                .replacingOccurrences(of: "^", with: "")
                .replacingOccurrences(of: " ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let numbers = source.components(separatedBy: ",").compactMap { Int($0) }
            var replacedLink: [String] = []
            for number in numbers {
                guard let result = contentLink[number] else { continue }
                replacedLink.append("[^\(number)](\(result))")
            }
            if replacedLink.isEmpty {
                continue
            }

            let range = match.range
            let type = map
                .first { $0.startIndex <= range.lowerBound && $0.endIndex >= range.upperBound }?
                .type

            if let type, prevent.contains(type) {
                Logger.model.debugFile("ignoring content inside block type: \(type)")
                continue
            }

            let replacement = replacedLink.joined(separator: " ")
            Logger.model.debugFile("replacing \(source) with \(replacement) at range \(range)")
            content.replaceSubrange(range, with: replacement)
        }

        return content
    }
}

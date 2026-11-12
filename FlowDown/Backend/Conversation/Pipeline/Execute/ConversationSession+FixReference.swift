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

/// Any footnote style marker, e.g. `[^1]`, `[^1, 2]` or `[^Date_001]`.
/// An already linked citation `[^1](https://…)` is not a match.
private let markerRegex = Regex {
    "[^"

    Capture {
        Repeat(1 ... 64) {
            CharacterClass.anyOf("[]\n\r").inverted
        }
    }

    "]"

    NegativeLookahead {
        "("
    }
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
        Self.resolveReferences(in: content, with: contentLink)
    }

    /// Links the citation markers that map to `contentLink`, then drops the
    /// markers that resolve to nothing, such as a model-invented `[^Date_001]`.
    static func resolveReferences(
        in content: String,
        with contentLink: [Int: String],
    ) -> String {
        if content.isEmpty { return content }
        let linked = linkWebReferences(in: content, with: contentLink)
        return removeUnresolvedReferences(in: linked, with: contentLink)
    }

    private static func linkWebReferences(
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

    private static func removeUnresolvedReferences(
        in content: String,
        with contentLink: [Int: String],
    ) -> String {
        let matches = content.matches(of: markerRegex)
        if matches.isEmpty { return content }

        let map = MarkdownParser().parseBlockRange(content)
        let definedLabels = footnoteDefinitionLabels(in: content)
        var codeSpanCache: [String.Index: [Range<String.Index>]] = [:]

        var removals: [Range<String.Index>] = []
        for match in matches {
            let range = match.range
            let label = String(match.output.1)
            if label.contains(where: \.isNewline) { continue }

            // `[^label]:` at the beginning of a line is a footnote definition.
            if content[range.upperBound...].first == ":",
               isBeginningOfLine(range.lowerBound, in: content)
            { continue }

            // a real Markdown footnote, the reply explains it by itself
            let normalized = normalize(label: label)
            let parts = normalized.components(separatedBy: ",").map { normalize(label: $0) }
            if definedLabels.contains(normalized) { continue }
            if parts.contains(where: { definedLabels.contains($0) }) { continue }

            // resolvable but left untouched on purpose by the linking pass
            let numbers = parts.compactMap { Int($0.replacingOccurrences(of: "^", with: "")) }
            if numbers.contains(where: { contentLink[$0] != nil }) { continue }

            let block = map.first { $0.startIndex <= range.lowerBound && $0.endIndex >= range.upperBound }
            if let block, prevent.contains(block.type) {
                // do not process content inside code block
                continue
            }

            // root block ranges do not describe inline code, look for it here
            let scope = if let block, block.startIndex < block.endIndex {
                block.startIndex ..< block.endIndex
            } else {
                content.startIndex ..< content.endIndex
            }
            let codeSpans: [Range<String.Index>]
            if let cached = codeSpanCache[scope.lowerBound] {
                codeSpans = cached
            } else {
                codeSpans = codeSpanRanges(in: content[scope])
                codeSpanCache[scope.lowerBound] = codeSpans
            }
            if codeSpans.contains(where: { $0.lowerBound <= range.lowerBound && $0.upperBound >= range.upperBound }) {
                continue
            }

            // take one leading space with it when the marker hangs before punctuation
            var lowerBound = range.lowerBound
            if lowerBound > content.startIndex {
                let before = content.index(before: lowerBound)
                let next = content[range.upperBound...].first
                let closesClause = next.map { $0.isWhitespace || $0.isPunctuation } ?? true
                if content[before] == " ", closesClause {
                    lowerBound = before
                }
            }

            Logger.model.debugFile("removing unresolved reference \(label)")
            removals.append(lowerBound ..< range.upperBound)
        }
        if removals.isEmpty { return content }

        var result = ""
        var cursor = content.startIndex
        for removal in removals {
            result += content[cursor ..< removal.lowerBound]
            cursor = removal.upperBound
        }
        result += content[cursor...]
        return result
    }

    private static func normalize(label: String) -> String {
        label.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// Whether `index` is preceded only by up to three spaces on its line.
    private static func isBeginningOfLine(_ index: String.Index, in content: String) -> Bool {
        var indent = 0
        var cursor = index
        while cursor > content.startIndex {
            let before = content.index(before: cursor)
            let character = content[before]
            if character.isNewline { return true }
            guard character == " ", indent < 3 else { return false }
            indent += 1
            cursor = before
        }
        return true
    }

    /// Labels defined by `[^label]: …` lines anywhere in the content.
    private static func footnoteDefinitionLabels(in content: String) -> Set<String> {
        var labels: Set<String> = []
        for match in content.matches(of: markerRegex) {
            guard content[match.range.upperBound...].first == ":",
                  isBeginningOfLine(match.range.lowerBound, in: content)
            else { continue }
            labels.insert(normalize(label: String(match.output.1)))
        }
        return labels
    }

    /// Ranges enclosed by matching backtick runs, covering inline code and
    /// the fenced code a root block range can not tell apart, e.g. in a list.
    private static func codeSpanRanges(in text: Substring) -> [Range<String.Index>] {
        var runs: [(range: Range<String.Index>, length: Int)] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == "`" else {
                index = text.index(after: index)
                continue
            }
            let start = index
            var length = 0
            while index < text.endIndex, text[index] == "`" {
                length += 1
                index = text.index(after: index)
            }
            runs.append((start ..< index, length))
        }

        var spans: [Range<String.Index>] = []
        var opening = 0
        while opening < runs.count {
            let closing = runs[(opening + 1)...].firstIndex { $0.length == runs[opening].length }
            if let closing {
                spans.append(runs[opening].range.lowerBound ..< runs[closing].range.upperBound)
                opening = closing + 1
            } else {
                opening += 1
            }
        }
        return spans
    }
}

//
//  ActivityStepText.swift
//  FlowDown
//

import UIKit

/// How a summary that lists its steps (`InlineActivityStepsSetting`) sets
/// them: plain text in the footnote font and the secondary colour, a thought
/// wrapped in full and a call on one line. The row lays its labels out with
/// the heights measured here, so a row is drawn at the height it was
/// measured at.
///
/// A thought runs to thousands of characters and grows while it streams. It
/// is set in pieces that break at a line break past `pieceLength`: the
/// pieces before the last stay the same as it grows, so only the last is
/// measured again, and no label grows taller than a few screens.
@MainActor
enum ActivityStepText {
    /// About how many bytes of a thought one label takes before the text
    /// continues in the next, at the next line break.
    static let pieceLength = 1024

    private struct Measure: Hashable {
        let text: String
        let wraps: Bool
        let font: UIFont
        let width: CGFloat
    }

    private static var heights: [Measure: CGFloat] = [:]
    /// Past this many heights the cache starts again: the last piece of a
    /// streaming thought is a new text each time it grows.
    private static let capacity = 512
    private static let sizing = UILabel()

    /// `text` in pieces, each next one after a line break: the break that
    /// first follows `pieceLength` bytes of a piece, unless it sits within
    /// a run of breaks. The break between two pieces is left out; any more
    /// in its run start the next piece, which a label draws as blank lines,
    /// so the pieces stacked read as the whole text in one label. A piece
    /// depends only on the text before its end, so the pieces of a growing
    /// text stay as they were but for the last.
    nonisolated static func pieces(of text: String) -> [String] {
        let utf8 = text.utf8
        guard utf8.count > pieceLength else { return [text] }
        var pieces: [String] = []
        var start = utf8.startIndex
        var index = start
        var length = 0
        var previous: UInt8 = 0
        while index != utf8.endIndex {
            let byte = utf8[index]
            if byte == UInt8(ascii: "\n"), previous != UInt8(ascii: "\n"), length >= pieceLength {
                pieces.append(String(text[start ..< index]))
                start = utf8.index(after: index)
                index = start
                length = 0
                previous = byte
                continue
            }
            previous = byte
            length += 1
            index = utf8.index(after: index)
        }
        pieces.append(String(text[start ..< utf8.endIndex]))
        return pieces
    }

    /// Sets a label up to draw a step's text.
    static func configure(_ label: UILabel, wraps: Bool, font: UIFont) {
        if label.font != font {
            label.font = font
        }
        label.textColor = .secondaryLabel
        label.numberOfLines = wraps ? 0 : 1
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
    }

    /// The height a label set up by `configure` draws `text` in at `width`.
    static func height(of text: String, wraps: Bool, font: UIFont, width: CGFloat) -> CGFloat {
        let measure = Measure(text: text, wraps: wraps, font: font, width: width)
        if let height = heights[measure] {
            return height
        }
        if heights.count >= capacity {
            heights.removeAll()
        }
        configure(sizing, wraps: wraps, font: font)
        sizing.text = text
        let size = sizing.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = ceil(size.height)
        heights[measure] = height
        return height
    }

    /// The pieces a step is set in: a thought's, or a call's one line.
    nonisolated static func pieces(of step: MessageListView.ActivitySummary.InlineStep) -> [String] {
        switch step.kind {
        case .thought: pieces(of: step.text)
        case .call: [step.text]
        }
    }

    /// The height of a step as the row stacks its pieces.
    static func height(of step: MessageListView.ActivitySummary.InlineStep, font: UIFont, width: CGFloat) -> CGFloat {
        let wraps = step.kind == .thought
        return pieces(of: step).reduce(0) { $0 + height(of: $1, wraps: wraps, font: font, width: width) }
    }
}

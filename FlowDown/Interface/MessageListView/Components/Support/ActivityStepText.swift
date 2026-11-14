//
//  ActivityStepText.swift
//  FlowDown
//

import LitextAnimation
import UIKit

/// How a summary that lists its steps (`InlineActivityStepsSetting`) sets
/// them: plain text in the footnote font and the secondary colour, a thought
/// wrapped in full and a call on one line. The row lays its labels out with
/// the heights measured here, so a row is drawn at the height it was
/// measured at.
///
/// A thought is drawn by the label the reply is drawn by, so its text fades
/// in as it streams, just as the reply's does (`ChatMarkdownView.reveal`).
/// A call is one line cut at its end, which that label does not do, so it
/// stays a `UILabel`.
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
    private static let thoughtSizing = LTXAnimatableLabel()

    /// One label's worth of a listed step.
    struct Piece: Hashable {
        /// The step and which of its pieces this is: the label showing it
        /// keeps it while the step is listed.
        let key: String
        let stepID: String
        let wraps: Bool
        let text: String
    }

    /// What listing other steps does to the pieces on screen.
    struct Change: Equatable {
        /// Pieces of steps not listed before: each comes in whole.
        var arrived: Set<String> = []
        /// New pieces of a thought already listed, which grew into them:
        /// they come in as its text does.
        var continued: Set<String> = []
        /// Pieces no longer listed.
        var departed: Set<String> = []

        nonisolated init(from old: [Piece], to new: [Piece]) {
            let oldKeys = Set(old.map(\.key))
            let oldSteps = Set(old.map(\.stepID))
            for piece in new where !oldKeys.contains(piece.key) {
                if oldSteps.contains(piece.stepID) {
                    continued.insert(piece.key)
                } else {
                    arrived.insert(piece.key)
                }
            }
            departed = oldKeys.subtracting(new.map(\.key))
        }
    }

    /// Every piece the steps are set in, in order.
    nonisolated static func pieces(of steps: [MessageListView.ActivitySummary.InlineStep]) -> [Piece] {
        steps.flatMap { step in
            pieces(of: step).enumerated().map { index, text in
                Piece(key: "\(step.id)#\(index)", stepID: step.id, wraps: step.kind == .thought, text: text)
            }
        }
    }

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

    /// Sets a label up to draw a call's line.
    static func configure(_ label: UILabel, wraps: Bool, font: UIFont) {
        if label.font != font {
            label.font = font
        }
        label.textColor = .secondaryLabel
        label.numberOfLines = wraps ? 0 : 1
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
    }

    /// A label for a thought's piece, which fades streamed text in as the
    /// reply does. It takes no touches: the row opens the trace.
    static func makeThoughtLabel() -> LTXAnimatableLabel {
        let label = LTXAnimatableLabel()
        label.animator = LTXFadeInAnimator(configuration: ChatMarkdownView.reveal)
        label.isUserInteractionEnabled = false
        label.isAccessibilityElement = true
        label.accessibilityTraits = .staticText
        return label
    }

    /// What sets a thought in its label as a `UILabel` set it, which listed
    /// thoughts before their text faded in: the lines that far apart, the
    /// first that far down.
    struct ThoughtSetting: Equatable {
        /// Added between lines: a `UILabel` gives each the font's leading,
        /// which the thought's label leaves out.
        let lineSpacing: CGFloat
        /// How far below the row's place for it the label sits, so its
        /// first line is drawn where a `UILabel` there drew it.
        let drop: CGFloat
    }

    private static var thoughtSettings: [UIFont: ThoughtSetting] = [:]

    /// Measured once a font: two lines in each label.
    static func thoughtSetting(for font: UIFont) -> ThoughtSetting {
        if let setting = thoughtSettings[font] {
            return setting
        }
        let fitting = CGSize(width: 1024, height: CGFloat.greatestFiniteMagnitude)
        configure(sizing, wraps: true, font: font)
        sizing.text = "A"
        let oneLine = sizing.sizeThatFits(fitting).height
        sizing.text = "A\nA"
        let twoLines = sizing.sizeThatFits(fitting).height
        // a label centres its text in the whole points it is given
        let baseline = font.ascender + (ceil(oneLine) - oneLine) / 2

        thoughtSizing.attributedText = NSAttributedString(string: "A\nA", attributes: [.font: font])
        thoughtSizing.frame = CGRect(origin: .zero, size: thoughtSizing.sizeThatFits(fitting))
        thoughtSizing.layoutIfNeeded()
        let baselines = thoughtSizing.layoutLines.map {
            thoughtSizing.viewRect(fromLayoutRect: CGRect(origin: $0.baselineOrigin, size: .zero)).minY
        }
        var setting = ThoughtSetting(lineSpacing: 0, drop: 0)
        if baselines.count == 2 {
            let scale = max(sizing.traitCollection.displayScale, 1)
            setting = ThoughtSetting(
                lineSpacing: max(0, twoLines - oneLine - (baselines[1] - baselines[0])),
                drop: (max(0, baseline - baselines[0]) * scale).rounded() / scale,
            )
        }
        thoughtSettings[font] = setting
        return setting
    }

    /// A thought's text as its label draws it.
    static func thoughtText(_ text: String, font: UIFont) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = thoughtSetting(for: font).lineSpacing
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: paragraph,
        ])
    }

    /// The height its label draws `text` in at `width`: a thought's
    /// (`makeThoughtLabel`), or a call's, set up by `configure`.
    static func height(of text: String, wraps: Bool, font: UIFont, width: CGFloat) -> CGFloat {
        let measure = Measure(text: text, wraps: wraps, font: font, width: width)
        if let height = heights[measure] {
            return height
        }
        if heights.count >= capacity {
            heights.removeAll()
        }
        let fitting = CGSize(width: width, height: .greatestFiniteMagnitude)
        let size: CGSize
        if wraps {
            thoughtSizing.attributedText = thoughtText(text, font: font)
            size = thoughtSizing.sizeThatFits(fitting)
        } else {
            configure(sizing, wraps: wraps, font: font)
            sizing.text = text
            size = sizing.sizeThatFits(fitting)
        }
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

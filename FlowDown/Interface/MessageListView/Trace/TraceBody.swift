//
//  TraceBody.swift
//  FlowDown
//

import Litext
import UIKit

/// The text a step's page in the trace shows (`TraceStepController`): a
/// thought's text, or a call by `ToolCallDetail` with each name set apart
/// from its value. A long call is decoded and laid out once for each text,
/// size and width, not again on every layout pass of the page.
@MainActor
enum TraceBody {
    struct Call: Hashable {
        let title: String
        let arguments: String
        let result: String

        nonisolated var detail: ToolCallDetail {
            ToolCallDetail(arguments: arguments, result: result, title: title)
        }
    }

    struct Key: Hashable {
        /// A thought's text; empty for a call.
        let source: String
        let call: Call?
        var size: UIContentSizeCategory = .unspecified
    }

    private struct Measure: Hashable {
        let key: Key
        let width: CGFloat
    }

    private static var texts: [Key: NSAttributedString] = [:]
    private static var heights: [Measure: CGFloat] = [:]
    private static let sizing = TextLabelView()
    /// Past this many texts, or four times as many heights, the caches
    /// start again: a step that streams is a new text each time it grows,
    /// and a long one's text is the size of what it carries.
    private static let capacity = 64

    static func text(for key: Key) -> NSAttributedString {
        if let text = texts[key] {
            return text
        }
        if texts.count >= capacity {
            texts.removeAll()
        }
        let text = build(key)
        texts[key] = text
        return text
    }

    /// The height the text takes at `width`, as a `TextLabelView` lays it out.
    static func height(for key: Key, width: CGFloat) -> CGFloat {
        let measure = Measure(key: key, width: width)
        if let height = heights[measure] {
            return height
        }
        if heights.count >= capacity * 4 {
            heights.removeAll()
        }
        sizing.attributedText = text(for: key)
        let height = ceil(sizing.sizeThatFits(CGSize(width: width, height: 0)).height)
        heights[measure] = height
        return height
    }

    private static func build(_ key: Key) -> NSAttributedString {
        let body: [NSAttributedString.Key: Any] = [
            .font: UIFont.preferredFont(forTextStyle: .body),
            .foregroundColor: UIColor.label,
        ]
        guard let call = key.call else {
            return NSAttributedString(string: key.source, attributes: body)
        }
        let footnote = UIFont.preferredFont(forTextStyle: .footnote)
        let name: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: footnote.pointSize, weight: .semibold),
            .foregroundColor: UIColor.secondaryLabel,
        ]
        let result = NSMutableAttributedString()
        for (index, section) in call.detail.sections.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n\n", attributes: body))
            }
            if let label = section.name {
                result.append(NSAttributedString(string: label + "\n", attributes: name))
            }
            result.append(NSAttributedString(string: section.value, attributes: body))
        }
        return result
    }
}

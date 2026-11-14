//
//  ActivityStepTypesettingTests.swift
//  FlowDownUnitTests
//

@preconcurrency @testable import FlowDown
import Foundation
import Litext
import LitextAnimation
import MarkdownView
import Testing
import UIKit

/// A listed thought is drawn by the reply's label so its text can fade in
/// (`ActivityStepText.makeThoughtLabel`). It has to read as it did in the
/// `UILabel` it replaced: as tall, in as many lines, each line where it was.
@Suite(.serialized)
@MainActor
struct ActivityStepTypesettingTests {
    private static let samples: [(name: String, text: String)] = [
        ("english", "The user is asking when the launch happened. I should look the dates up first, compare the two sources, and only then answer, because the earlier answer mixed up the announcement with the release itself."),
        ("chinese", "用户想知道发布会的具体日期。我需要先查找相关资料，对比两个来源的说法，然后再给出答案，因为之前的回答把公布时间和正式发售时间混淆了。"),
        ("mixed", "先用 web_search 查一下 iPhone 17 Pro 的发布日期 (2025 年 9 月)，然后 compare the two results 并确认 time zone 是否为 UTC+8，最后再回答用户。"),
        ("paragraphs", "The user greeted me, so there is nothing to look up and I can answer properly.\n\nI should respond first with a short greeting, then ask what they would like help with today.\n\n再用中文补充一句，方便用户继续提问。"),
        ("short", "One more page."),
    ]
    private static let widths: [CGFloat] = [320, 358]

    @Test
    func `a thought is set as tall, in as many lines and in the same places as before`() throws {
        let footnote = MessageListView().theme.fonts.footnote
        let larger = UIFont.preferredFont(
            forTextStyle: .footnote,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraExtraLarge),
        )
        for font in [footnote, larger] {
            try check(font: font)
        }
    }

    private func check(font: UIFont) throws {
        print("TYPESET font \(font.pointSize) setting \(ActivityStepText.thoughtSetting(for: font))")
        for sample in Self.samples {
            for width in Self.widths {
                // As on origin/main: `ActivityStepText.configure(_:wraps:font:)`
                // with `wraps`, at the height `sizeThatFits` gave.
                let old = UILabel()
                old.font = font
                old.textColor = .secondaryLabel
                old.numberOfLines = 0
                old.lineBreakMode = .byWordWrapping
                old.text = sample.text
                let oldHeight = ceil(old.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
                old.frame = CGRect(x: 0, y: 0, width: width, height: oldHeight)
                old.layoutIfNeeded()

                // As the row sets it now.
                let new = ActivityStepText.makeThoughtLabel()
                new.attributedText = ActivityStepText.thoughtText(sample.text, font: font)
                let newHeight = ActivityStepText.height(of: sample.text, wraps: true, font: font, width: width)
                let drop = ActivityStepText.thoughtSetting(for: font).drop
                new.frame = CGRect(x: 0, y: 0, width: width, height: newHeight)
                new.layoutIfNeeded()
                // the row puts the label that far down; drawn here in a view
                // that stands for the row's place for it
                let place = UIView(frame: CGRect(x: 0, y: 0, width: width, height: newHeight + 1))
                new.frame.origin.y = drop
                place.addSubview(new)

                let lines = new.layoutLines.map { new.viewRect(fromLayoutRect: $0.rect).offsetBy(dx: 0, dy: drop) }
                let oldLineCount = Self.lineCount(of: old, width: width)
                print("TYPESET \(font.pointSize) \(sample.name) w=\(Int(width)) height old=\(oldHeight) new=\(newHeight) lines old=\(oldLineCount) new=\(lines.count)")
                #expect(abs(newHeight - oldHeight) <= 1, "\(font.pointSize)pt \(sample.name) at \(width)")
                #expect(lines.count == oldLineCount, "\(font.pointSize)pt \(sample.name) at \(width)")

                // Each line's ink, in the rows the new label gives the line:
                // where it starts and ends, across and down.
                let canvas = CGSize(width: width, height: max(oldHeight, newHeight) + 1)
                let oldInk = Ink(of: old, canvas: canvas)
                let newInk = Ink(of: place, canvas: canvas)
                #expect(oldInk.total > 0 && newInk.total > 0)
                for (index, line) in lines.enumerated() {
                    let was = oldInk.extent(fromY: line.minY, toY: line.maxY)
                    let now = newInk.extent(fromY: line.minY, toY: line.maxY)
                    print("TYPESET \(font.pointSize) \(sample.name) w=\(Int(width)) line \(index) box y=\(line.minY)...\(line.maxY) old ink=\(was.map(Self.describe) ?? "none") new ink=\(now.map(Self.describe) ?? "none")")
                    guard let was, let now else {
                        #expect(was == nil && now == nil, "\(font.pointSize)pt \(sample.name) at \(width), line \(index)")
                        continue
                    }
                    #expect(abs(was.minY - now.minY) <= 0.5, "\(font.pointSize)pt \(sample.name) at \(width), line \(index) top")
                    #expect(abs(was.maxY - now.maxY) <= 0.5, "\(font.pointSize)pt \(sample.name) at \(width), line \(index) bottom")
                    #expect(abs(was.minX - now.minX) <= 1, "\(font.pointSize)pt \(sample.name) at \(width), line \(index) left")
                    #expect(abs(was.maxX - now.maxX) <= 1, "\(font.pointSize)pt \(sample.name) at \(width), line \(index) right")
                }
                // And drawn in the same grey.
                print("TYPESET \(font.pointSize) \(sample.name) w=\(Int(width)) ink old=\(oldInk.total) new=\(newInk.total) peak old=\(oldInk.peak) new=\(newInk.peak)")
                #expect(abs(Double(oldInk.total) - Double(newInk.total)) <= Double(oldInk.total) * 0.03, "\(font.pointSize)pt \(sample.name) at \(width)")
                #expect(abs(Int(oldInk.peak) - Int(newInk.peak)) <= 2, "\(font.pointSize)pt \(sample.name) at \(width)")
            }
        }
    }

    /// How many lines a `UILabel` sets its text in: its height over the
    /// height each line more adds.
    private static func lineCount(of label: UILabel, width: CGFloat) -> Int {
        let fitting = CGSize(width: width, height: .greatestFiniteMagnitude)
        let height = label.sizeThatFits(fitting).height
        let probe = UILabel()
        probe.font = label.font
        probe.numberOfLines = 0
        probe.lineBreakMode = label.lineBreakMode
        probe.text = "A"
        let oneLine = probe.sizeThatFits(fitting).height
        probe.text = "A\nA"
        let pitch = probe.sizeThatFits(fitting).height - oneLine
        return Int(((height - oneLine) / pitch).rounded()) + 1
    }

    private static func describe(_ rect: CGRect) -> String {
        "x \(rect.minX)...\(rect.maxX) y \(rect.minY)...\(rect.maxY)"
    }
}

/// How opaque a view draws each pixel, at 4 pixels a point.
@MainActor
private struct Ink {
    static let scale: CGFloat = 4
    let width: Int
    let height: Int
    private let alpha: [UInt8]

    init(of view: UIView, canvas: CGSize) {
        let width = Int((canvas.width * Self.scale).rounded(.up))
        let height = Int((canvas.height * Self.scale).rounded(.up))
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return }
            context.translateBy(x: 0, y: CGFloat(height))
            context.scaleBy(x: Self.scale, y: -Self.scale)
            UIGraphicsPushContext(context)
            view.layer.render(in: context)
            UIGraphicsPopContext()
        }
        alpha = stride(from: 3, to: pixels.count, by: 4).map { pixels[$0] }
        self.width = width
        self.height = height
    }

    var total: Int {
        alpha.reduce(0) { $0 + Int($1) }
    }

    var peak: UInt8 {
        alpha.max() ?? 0
    }

    /// The box of what is drawn between two heights, in points.
    func extent(fromY top: CGFloat, toY bottom: CGFloat) -> CGRect? {
        let firstRow = max(0, Int((top * Self.scale).rounded()))
        let lastRow = min(height, Int((bottom * Self.scale).rounded()))
        var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
        for row in firstRow ..< max(firstRow, lastRow) {
            for column in 0 ..< width where alpha[row * width + column] > 24 {
                minX = min(minX, column)
                maxX = max(maxX, column)
                minY = min(minY, row)
                maxY = max(maxY, row)
            }
        }
        guard minX <= maxX else { return nil }
        return CGRect(
            x: CGFloat(minX) / Self.scale,
            y: CGFloat(minY) / Self.scale,
            width: CGFloat(maxX - minX + 1) / Self.scale,
            height: CGFloat(maxY - minY + 1) / Self.scale,
        )
    }
}

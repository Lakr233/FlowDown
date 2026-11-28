@preconcurrency @testable import FlowDown
import Foundation
import Litext
import MarkdownParser
import MarkdownView
import Testing
import UIKit

@Suite(.serialized)
struct ChatMarkdownViewTests {
    @MainActor
    private func content(_ text: String, theme: MarkdownTheme) -> MarkdownContent {
        MarkdownContent(repairing: MarkdownParser().parse(text), theme: theme)
    }

    /// The colour of the first run set in the inline code font.
    @MainActor
    private func inlineCodeColor(in view: ChatMarkdownView) throws -> UIColor {
        let text = view.textLabelView.attributedText
        var color: UIColor?
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { font, range, stop in
            guard let font = font as? UIFont, font == view.theme.fonts.codeInline else { return }
            color = text.attribute(.foregroundColor, at: range.location, effectiveRange: nil) as? UIColor
            stop.pointee = true
        }
        return try #require(color)
    }

    @Test
    @MainActor
    func `inline code keeps one color object from one rebuild to the next`() throws {
        let view = ChatMarkdownView()
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 400)
        view.setContentImmediately(content("Call `first()` now.", theme: view.theme))
        let first = try inlineCodeColor(in: view)
        // A dynamic color equals only itself, so a new one for the same theme
        // would make the label typeset everything from here on again.
        view.setContentImmediately(content("Call `first()` now. And then `second()` as well.", theme: view.theme))
        #expect(try inlineCodeColor(in: view) === first)

        var theme = view.theme
        theme.colors.code = .systemPurple
        view.theme = theme
        view.setContentImmediately(content("Call `first()` now.", theme: theme))
        let recolored = try inlineCodeColor(in: view)
        #expect(recolored !== first)
        #expect(recolored.resolvedColor(with: .current).cgColor.alpha < 1)
    }

    @Test
    @MainActor
    func `a reply draws a tall text in tiles and a view made while that is off does not`() {
        let setting = ChatMarkdownView.tiledDrawing
        defer { ChatMarkdownView.tiledDrawing = setting }
        // On wherever the app runs.
        #expect(setting == TextLabelView.TiledDrawing())

        ChatMarkdownView.tiledDrawing = .init()
        #expect(ChatMarkdownView().textLabelView.tiledDrawing == TextLabelView.TiledDrawing())

        ChatMarkdownView.tiledDrawing = nil
        #expect(ChatMarkdownView().textLabelView.tiledDrawing == nil)
    }

    /// The list asks every reply on screen after it lays out. Only a reply
    /// drawn in tiles, and tall enough to be, is given a layout pass for it.
    @Test
    @MainActor
    func `only a tiled reply is laid out again after the list moves its rows`() {
        let setting = ChatMarkdownView.tiledDrawing
        defer { ChatMarkdownView.tiledDrawing = setting }
        let text = (0 ..< 40).map { "Paragraph \($0) of a reply long enough to pass the threshold." }.joined(separator: "\n\n")

        func row(tiled: TextLabelView.TiledDrawing?, markdown: String, height: CGFloat) -> AiMessageView {
            ChatMarkdownView.tiledDrawing = tiled
            let row = AiMessageView()
            row.frame = CGRect(x: 0, y: 0, width: 400, height: height)
            row.markdownView.setContentImmediately(content(markdown, theme: row.markdownView.theme))
            row.layoutIfNeeded()
            row.markdownView.layoutIfNeeded()
            row.markdownView.textLabelView.layoutIfNeeded()
            return row
        }

        let tiled = row(tiled: .init(threshold: 300), markdown: text, height: 2400)
        #expect(tiled.markdownView.textLabelView.bounds.height > 300)
        #expect(!tiled.markdownView.textLabelView.layer.needsLayout())
        tiled.updateTilesAfterListLayout()
        #expect(tiled.markdownView.textLabelView.layer.needsLayout())

        let short = row(tiled: .init(threshold: 300), markdown: "One line.", height: 60)
        #expect(short.markdownView.textLabelView.bounds.height <= 300)
        short.updateTilesAfterListLayout()
        #expect(!short.markdownView.textLabelView.layer.needsLayout())

        let untiled = row(tiled: nil, markdown: text, height: 2400)
        untiled.updateTilesAfterListLayout()
        #expect(!untiled.markdownView.textLabelView.layer.needsLayout())
    }
}

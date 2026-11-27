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
}

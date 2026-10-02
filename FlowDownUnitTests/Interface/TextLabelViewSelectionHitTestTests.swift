@testable import FlowDown
import Litext
import Testing
import UIKit

@MainActor
struct TextLabelViewSelectionHitTestTests {
    private func makeLabel(_ text: String, frame: CGRect, in container: UIView) -> TextLabelView {
        let label = TextLabelView()
        label.isSelectable = true
        label.attributedText = NSAttributedString(
            string: text,
            attributes: [.font: UIFont.systemFont(ofSize: 17)],
        )
        label.frame = frame
        label.preferredMaxLayoutWidth = frame.width
        container.addSubview(label)
        return label
    }

    private func makeWindow() -> UIWindow {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 400))
        window.rootViewController = UIViewController()
        window.isHidden = false
        return window
    }

    @Test
    func selectionContains_groupSelectionUnderAnotherMember_reportsHit() throws {
        let window = makeWindow()
        defer { window.isHidden = true }
        let container = try #require(window.rootViewController?.view)
        let first = makeLabel("Alpha", frame: CGRect(x: 20, y: 20, width: 160, height: 40), in: container)
        let second = makeLabel("Beta", frame: CGRect(x: 200, y: 20, width: 160, height: 40), in: container)
        let group = TextSelectionGroup(labels: [first, second])
        container.layoutIfNeeded()
        group.selectAll()
        #expect(group.selectedSegments.count == 2)

        let rect = try #require(second.textLayout.rects(for: NSRange(location: 0, length: 4)).first)
        let pointInSecond = container.convert(second.viewRect(fromLayoutRect: rect).center, from: second)

        #expect(first.selectionContains(pointInSecond, from: container))
        #expect(second.selectionContains(pointInSecond, from: container))
        #expect(!first.selectionContains(CGPoint(x: 200, y: 300), from: container))
        withExtendedLifetime(group) {}
    }

    @Test
    func selectionContains_labelOutsideGroup_checksOnlyItsOwnSelection() throws {
        let window = makeWindow()
        defer { window.isHidden = true }
        let container = try #require(window.rootViewController?.view)
        let label = makeLabel("Gamma", frame: CGRect(x: 20, y: 100, width: 160, height: 40), in: container)
        let other = makeLabel("Delta", frame: CGRect(x: 200, y: 100, width: 160, height: 40), in: container)
        container.layoutIfNeeded()
        label.selectionRange = NSRange(location: 0, length: 5)
        other.selectionRange = NSRange(location: 0, length: 5)

        let rect = try #require(other.textLayout.rects(for: NSRange(location: 0, length: 5)).first)
        let pointInOther = container.convert(other.viewRect(fromLayoutRect: rect).center, from: other)

        #expect(!label.selectionContains(pointInOther, from: container))
        #expect(other.selectionContains(pointInOther, from: container))
    }
}

private extension CGRect {
    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }
}

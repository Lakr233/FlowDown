@preconcurrency @testable import FlowDown
import Foundation
import MarkdownView
import Storage
import Testing
import UIKit

/// A pan recognizer whose position and phase the test drives directly, since a
/// real one only moves in response to touches the test cannot deliver.
private final class StubPanGestureRecognizer: UIPanGestureRecognizer {
    var stubLocation: CGPoint = .zero
    var stubState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func location(in _: UIView?) -> CGPoint { stubLocation }
}

@Suite(.serialized)
struct SidebarResizeTests {
    @MainActor
    private func makeDragger() -> (SidebarDraggerView, StubPanGestureRecognizer) {
        let host = UIView(frame: .init(x: 0, y: 0, width: 1200, height: 800))
        let dragger = SidebarDraggerView()
        host.addSubview(dragger)
        return (dragger, StubPanGestureRecognizer())
    }

    @MainActor
    private func drag(_ dragger: SidebarDraggerView, _ gesture: StubPanGestureRecognizer, to x: CGFloat) {
        gesture.stubLocation = .init(x: x, y: 100)
        dragger.handleDrag(gesture)
    }

    @Test
    @MainActor
    func `reversing at the minimum width moves the sidebar on the very next sample`() {
        let (dragger, gesture) = makeDragger()
        dragger.currentValue = 300

        gesture.stubState = .began
        drag(dragger, gesture, to: 500)
        gesture.stubState = .changed

        // Push well past the minimum. The width pins, but the pointer keeps going.
        drag(dragger, gesture, to: 340)
        #expect(dragger.currentValue == dragger.allowedMinimalValue)
        drag(dragger, gesture, to: 300)
        #expect(dragger.currentValue == dragger.allowedMinimalValue)

        // Turning around has to take effect immediately. Measuring from where the
        // drag began would make the pointer travel back 140pt before anything
        // happened, which reads as the divider ignoring the drag.
        drag(dragger, gesture, to: 310)
        #expect(dragger.currentValue > dragger.allowedMinimalValue)
        drag(dragger, gesture, to: 330)
        #expect(dragger.currentValue >= dragger.allowedMinimalValue + 30)
    }

    @Test
    @MainActor
    func `pushing further past the minimum still reaches the collapse threshold`() {
        let (dragger, gesture) = makeDragger()
        dragger.currentValue = 300
        var didSuggestCollapse = false
        dragger.onSuggestCollapse = {
            didSuggestCollapse = true
            return true
        }

        gesture.stubState = .began
        drag(dragger, gesture, to: 500)
        gesture.stubState = .changed
        for x in stride(from: CGFloat(480), through: 200, by: -20) {
            drag(dragger, gesture, to: x)
        }

        #expect(didSuggestCollapse)
    }

    @Test
    @MainActor
    func `the width reaches user defaults only once the drag ends`() {
        let key = "SidebarWidth"
        let defaults = UserDefaults.standard
        let original = defaults.integer(forKey: key)
        defer { defaults.set(original, forKey: key) }

        let (dragger, gesture) = makeDragger()
        dragger.currentValue = 300
        defaults.set(-1, forKey: key)

        gesture.stubState = .began
        drag(dragger, gesture, to: 500)
        gesture.stubState = .changed
        drag(dragger, gesture, to: 540)
        drag(dragger, gesture, to: 560)
        #expect(defaults.integer(forKey: key) == -1)

        gesture.stubState = .ended
        drag(dragger, gesture, to: 560)
        #expect(defaults.integer(forKey: key) == dragger.currentValue)
    }

    @Test
    @MainActor
    func `the width the layout can honour bounds the drag`() {
        let (dragger, gesture) = makeDragger()
        dragger.currentValue = 300
        dragger.layoutMaximalValue = 360

        gesture.stubState = .began
        drag(dragger, gesture, to: 500)
        gesture.stubState = .changed
        drag(dragger, gesture, to: 700)
        #expect(dragger.currentValue == 360)

        // Coming back has to move it immediately rather than first undoing the
        // travel the layout never used.
        drag(dragger, gesture, to: 680)
        #expect(dragger.currentValue < 360)
    }
}

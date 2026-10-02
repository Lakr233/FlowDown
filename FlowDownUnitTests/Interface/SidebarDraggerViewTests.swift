@preconcurrency @testable import FlowDown
import Foundation
import Testing
import UIKit

/// A pan recognizer whose position and phase the test drives directly, since a
/// real one only moves in response to touches the test cannot deliver.
private final class StubDragGestureRecognizer: UIPanGestureRecognizer {
    var stubLocation: CGPoint = .zero
    var stubState: UIGestureRecognizer.State = .possible

    override var state: UIGestureRecognizer.State {
        get { stubState }
        set { stubState = newValue }
    }

    override func location(in _: UIView?) -> CGPoint { stubLocation }
}

@Suite(.serialized)
struct SidebarDraggerViewTests {
    @MainActor
    private func drag(_ dragger: SidebarDraggerView, _ gesture: StubDragGestureRecognizer, to x: CGFloat) {
        gesture.stubLocation = .init(x: x, y: 100)
        dragger.handleDrag(gesture)
    }

    @Test
    @MainActor
    func sidebarDrag_storedWidthAboveLayoutLimit_tracksPointer() {
        let key = "SidebarWidth"
        let defaults = UserDefaults.standard
        let original = defaults.object(forKey: key)
        defer { defaults.set(original, forKey: key) }

        let dragger = SidebarDraggerView()
        let gesture = StubDragGestureRecognizer()

        // The stored width was set in a wider window. This one leaves room
        // for only 400pt, so that is what is on screen.
        dragger.currentValue = 500
        dragger.layoutMaximalValue = 400

        gesture.stubState = .began
        drag(dragger, gesture, to: 500)
        #expect(dragger.currentValue == 400)
        gesture.stubState = .changed

        // The separator has to move with the pointer straight away instead of
        // first burning off the 100pt the window cannot show.
        drag(dragger, gesture, to: 450)
        #expect(dragger.currentValue == 350)
        drag(dragger, gesture, to: 400)
        #expect(dragger.currentValue == 300)
    }
}

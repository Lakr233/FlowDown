@preconcurrency @testable import FlowDown
import Foundation
import Testing
import UIKit

@Suite(.serialized)
struct ChatTopEdgeBandTests {
    @Test
    func topEdgeHeight_duoClosed_endsButtonMarginBelowButtons() {
        // iPhone Duo closed: the status bar is a column at the side, so the
        // safe area starts at the top of the screen.
        let height = FloatingChrome.topEdgeHeight(safeAreaTop: 0, buttonTop: 8, buttonBottom: 52)
        #expect(height == 60)
    }

    @Test
    func topEdgeHeight_notchedPhone_measuresMarginFromSafeArea() {
        let height = FloatingChrome.topEdgeHeight(safeAreaTop: 62, buttonTop: 70, buttonBottom: 114)
        #expect(height == 122)
    }

    @Test
    func topEdgeHeight_buttonAboveSafeArea_neverEndsAboveButtons() {
        let height = FloatingChrome.topEdgeHeight(safeAreaTop: 20, buttonTop: 10, buttonBottom: 54)
        #expect(height == 54)
    }

    #if !targetEnvironment(macCatalyst)
        @Test
        @MainActor
        func chatView_topEdge_isCentredOnTitleRow() async throws {
            try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
            for safeAreaTop: CGFloat in [0, 62] {
                let controller = UIViewController()
                controller.additionalSafeAreaInsets = UIEdgeInsets(top: safeAreaTop, left: 0, bottom: 0, right: 0)
                let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
                window.rootViewController = controller
                window.isHidden = false
                defer { window.isHidden = true }

                let chatView = ChatView()
                chatView.frame = controller.view.bounds
                controller.view.addSubview(chatView)
                chatView.layoutIfNeeded()

                let blur = try #require(chatView.topEdgeBlur)
                let button = chatView.escapeButton.convert(chatView.escapeButton.bounds, to: chatView)
                let safeTop = chatView.safeAreaInsets.top
                let marginAbove = button.minY - safeTop
                let marginBelow = blur.frame.maxY - button.maxY

                #expect(blur.frame.minY == 0)
                #expect(marginAbove > 0)
                #expect(marginBelow == marginAbove)
            }
        }
    #endif
}

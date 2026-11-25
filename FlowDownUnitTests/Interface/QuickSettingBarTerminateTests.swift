@testable import FlowDown
import Testing
import UIKit

@MainActor
struct QuickSettingBarTerminateTests {
    private func makeBar(width: CGFloat = 600, modelName: String = "Model") -> QuickSettingBar {
        let bar = QuickSettingBar()
        bar.translatesAutoresizingMaskIntoConstraints = true
        bar.frame = CGRect(x: 0, y: 0, width: width, height: 40)
        bar.setModelName(modelName)
        bar.layoutIfNeeded()
        return bar
    }

    @Test func terminateButton_startsHiddenAndOutOfLayout() {
        let bar = makeBar()

        #expect(bar.terminateButton.isHidden)
        #expect(!bar.isTerminateVisible)
        #expect(bar.scrollView.contentSize.width == bar.toolsToggle.frame.maxX)
    }

    @Test func terminateButton_sitsRightOfToolsWithStandardGap() {
        let bar = makeBar()
        let modelWidth = bar.modelPicker.bounds.width
        let toolsWidth = bar.toolsToggle.bounds.width

        bar.setTerminateVisible(true, animated: false)

        #expect(!bar.terminateButton.isHidden)
        #expect(bar.terminateButton.frame.minX == bar.toolsToggle.frame.maxX + 10)
        #expect(bar.modelPicker.bounds.width == modelWidth)
        #expect(bar.toolsToggle.bounds.width == toolsWidth)
        #expect(bar.scrollView.frame.midX == bar.bounds.midX)
    }

    @Test func terminateButton_tapCancelsOnceThenStaysDisabledUntilHidden() {
        let bar = makeBar()
        var cancelCount = 0
        bar.terminateAction = { cancelCount += 1 }
        bar.setTerminateVisible(true, animated: false)

        bar.terminateButton.actionBlock()
        bar.terminateButton.actionBlock()

        #expect(cancelCount == 1)
        #expect(!bar.terminateButton.isEnabled)

        bar.setTerminateVisible(false, animated: false)
        bar.setTerminateVisible(true, animated: false)

        #expect(bar.terminateButton.isEnabled)
    }

    @Test func overflowingRow_revealsButtonOnceAndRespectsManualScroll() {
        let bar = makeBar(width: 200, modelName: String(repeating: "Long Model Name ", count: 4))

        bar.setTerminateVisible(true, animated: false)

        let maxOffset = bar.scrollView.contentSize.width - bar.scrollView.bounds.width
        #expect(bar.scrollView.contentOffset.x == maxOffset)
        #expect(bar.terminateButton.frame.maxX <= bar.scrollView.contentOffset.x + bar.scrollView.bounds.width)

        bar.scrollView.contentOffset.x = 0
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        #expect(bar.scrollView.contentOffset.x == 0)
    }

    @Test func hidingButton_restoresLeadingOffset() {
        let bar = makeBar(width: 200, modelName: String(repeating: "Long Model Name ", count: 4))
        bar.setTerminateVisible(true, animated: false)
        #expect(bar.scrollView.contentOffset.x > 0)

        bar.setTerminateVisible(false, animated: false)

        #expect(bar.scrollView.contentOffset.x == 0)
        #expect(bar.terminateButton.isHidden)
    }

    @Test func conversationSwitch_whileHidden_resetsOffset() {
        let bar = makeBar(width: 200, modelName: String(repeating: "Long Model Name ", count: 4))
        bar.scrollView.contentOffset.x = 40

        bar.setTerminateVisible(false, animated: false)

        #expect(bar.scrollView.contentOffset.x == 0)
    }

    @Test func restoredOffset_isNotForcedOnLaterLayouts() {
        let bar = makeBar(width: 200, modelName: String(repeating: "Long Model Name ", count: 4))
        bar.setTerminateVisible(true, animated: false)
        bar.setTerminateVisible(false, animated: false)

        bar.scrollView.contentOffset.x = 40
        bar.setNeedsLayout()
        bar.layoutIfNeeded()

        #expect(bar.scrollView.contentOffset.x == 40)
    }

    @Test func animatedHide_restoresLeadingOffset() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        let bar = makeBar(width: 200, modelName: String(repeating: "Long Model Name ", count: 4))
        window.addSubview(bar)
        window.isHidden = false
        bar.setTerminateVisible(true, animated: false)
        #expect(bar.scrollView.contentOffset.x > 0)

        bar.setTerminateVisible(false)
        try await Task.sleep(for: .milliseconds(600))

        #expect(bar.scrollView.contentOffset.x == 0)
        #expect(bar.terminateButton.isHidden)
        window.isHidden = true
    }

    @Test func reversedDisappearance_leavesButtonVisible() async throws {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 200))
        let bar = makeBar()
        window.addSubview(bar)
        window.isHidden = false
        bar.setTerminateVisible(true, animated: false)

        bar.setTerminateVisible(false)
        #expect(!bar.terminateButton.isHidden)
        bar.setTerminateVisible(true)
        try await Task.sleep(for: .milliseconds(600))

        #expect(bar.isTerminateVisible)
        #expect(!bar.terminateButton.isHidden)
        #expect(bar.terminateButton.alpha == 1)
        #expect(bar.terminateButton.transform == .identity)
        window.isHidden = true
    }
}

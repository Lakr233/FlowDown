@testable import FlowDown
import Testing
import UIKit

struct ChatKeyboardLayoutTests {
    #if !targetEnvironment(macCatalyst)
        @Test
        @MainActor
        func `main controller keeps the chat host at full height`() {
            let controller = MainController()
            controller.loadViewIfNeeded()

            #expect(
                hasConstraint(
                    in: controller.contentView,
                    controller.contentView.contentView,
                    .bottom,
                    controller.contentView,
                    .bottom,
                ),
            )
            #expect(
                !hasConstraint(
                    in: controller.contentView,
                    controller.contentView.contentView,
                    .bottom,
                    controller.contentView.keyboardLayoutGuide,
                    .top,
                ),
            )
            #expect(
                hasConstraint(
                    in: controller.contentView.contentView,
                    controller.chatView,
                    .bottom,
                    controller.contentView.contentView,
                    .bottom,
                ),
            )
        }

        @Test
        @MainActor
        func `chat editor follows the keyboard layout guide`() {
            let chatView = ChatView()

            #expect(!chatView.keyboardLayoutGuide.usesBottomSafeArea)
            #expect(
                hasConstraint(
                    in: chatView,
                    chatView.editor,
                    .bottom,
                    chatView.keyboardLayoutGuide,
                    .top,
                ),
            )
        }
    #else
        @Test
        @MainActor
        func `catalyst chat editor remains anchored to the chat view bottom`() {
            let chatView = ChatView()

            #expect(
                hasConstraint(
                    in: chatView,
                    chatView.editor,
                    .bottom,
                    chatView,
                    .bottom,
                ),
            )
        }
    #endif

    private func hasConstraint(
        in owner: UIView,
        _ firstItem: AnyObject,
        _ firstAttribute: NSLayoutConstraint.Attribute,
        _ secondItem: AnyObject,
        _ secondAttribute: NSLayoutConstraint.Attribute,
    ) -> Bool {
        owner.constraints.contains { constraint in
            constraint.isActive
                && (constraint.firstItem as AnyObject?) === firstItem
                && constraint.firstAttribute == firstAttribute
                && (constraint.secondItem as AnyObject?) === secondItem
                && constraint.secondAttribute == secondAttribute
        }
    }
}

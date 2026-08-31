@testable import FlowDown
import Storage
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

extension ChatKeyboardLayoutTests {
    #if !targetEnvironment(macCatalyst)
        /// The maintainer's concern on #289 is that pinning only the editor to the keyboard
        /// guide, while the list fills the whole view, would put the bottom of the list under
        /// the editor and make the last message unreachable.
        ///
        /// It does not, because `updateCurrentMessageListInsets()` derives the list's bottom
        /// content inset from the editor's frame on every layout pass. This asserts that
        /// invariant directly: the list's usable content region must always stop at or above
        /// the top of the editor, at any view height.
        @Test
        @MainActor
        func `message list content stays clear of the editor at any height`() async throws {
            try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
            let conversation = sdb.conversationMake { conversation in
                conversation.update(\.title, to: "Keyboard Layout \(UUID().uuidString.prefix(8))")
            }
            defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }

            let chatView = ChatView()
            chatView.conversationIdentifier = conversation.id

            // keyboardLayoutGuide only resolves for a view inside a window.
            let window = UIWindow(frame: .init(x: 0, y: 0, width: 390, height: 640))
            window.addSubview(chatView)
            window.makeKeyAndVisible()

            for height in [640.0, 800.0, 1000.0] as [CGFloat] {
                window.frame = .init(x: 0, y: 0, width: 390, height: height)
                chatView.frame = window.bounds
                chatView.setNeedsLayout()
                chatView.layoutIfNeeded()

                guard let listView = chatView.currentMessageListView else {
                    #expect(Bool(false), "expected a message list view at height \(height)")
                    continue
                }

                let editorTop = min(chatView.editor.frame.minY, chatView.editorBackgroundView.frame.minY)
                let contentBottom = chatView.bounds.height - listView.contentSafeAreaInsets.bottom

                #expect(
                    listView.contentSafeAreaInsets.bottom > 0,
                    "list must reserve room for the editor at height \(height)",
                )
                #expect(
                    contentBottom <= editorTop,
                    "content region (\(contentBottom)) must end at or above the editor top (\(editorTop)) at height \(height)",
                )
            }
        }
    #endif
}

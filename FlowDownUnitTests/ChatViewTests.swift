@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing
import UIKit

@Suite(.serialized)
struct ChatViewTests {
    @Test
    @MainActor
    func prepareForReuse_executingConversation_keepsListViewInHierarchy() async throws {
        try await withTwoConversations { first, second in
            let controller = UIViewController()
            let chatView = ChatView()
            chatView.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
            controller.view.addSubview(chatView)

            chatView.use(conversation: first)
            let firstListView = try #require(chatView.currentMessageListView)
            #expect(firstListView.superview === chatView)

            ConversationSessionManager.shared.markSessionExecuting(first)
            defer { ConversationSessionManager.shared.markSessionCompleted(first) }

            // The sidebar selection path: MainController.load runs prepareForReuse before use.
            chatView.prepareForReuse()
            chatView.use(conversation: second)

            // The running stream anchors tool confirmations to this view, so it
            // must still resolve a view controller through the responder chain.
            #expect(firstListView.superview === chatView)
            #expect(firstListView.isHidden)
            #expect(owningViewController(of: firstListView) === controller)

            chatView.prepareForReuse()
            chatView.use(conversation: first)

            #expect(chatView.currentMessageListView === firstListView)
            #expect(firstListView.superview === chatView)
            #expect(!firstListView.isHidden)
        }
    }

    @MainActor
    private func withTwoConversations(
        _ body: @MainActor (Conversation.ID, Conversation.ID) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let first = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Chat View A \(UUID().uuidString.prefix(8))")
        }
        let second = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Chat View B \(UUID().uuidString.prefix(8))")
        }
        // ChatView drops list views of conversations the manager does not list.
        ConversationManager.shared.scanAll()

        defer {
            ConversationManager.shared.deleteConversation(identifier: first.id)
            ConversationManager.shared.deleteConversation(identifier: second.id)
        }
        try await body(first.id, second.id)
    }

    @MainActor
    private func owningViewController(of view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController {
                return controller
            }
            responder = current.next
        }
        return nil
    }
}

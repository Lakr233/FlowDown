@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing
import UIKit

@Suite(.serialized)
struct MessageListErrorRowTests {
    @Test
    func `error document round trips its description`() {
        let document = ReplyErrorDocument.document(for: "The request timed out.")
        #expect(ReplyErrorDocument.description(in: document) == "The request timed out.")
        #expect(ReplyErrorDocument.description(in: document, isStreaming: true) == "The request timed out.")
    }

    @Test
    func `failures saved with a bare fence count once the reply is done`() {
        let legacy = "```\nInvalid API key."
        #expect(ReplyErrorDocument.description(in: legacy) == "Invalid API key.")
        #expect(ReplyErrorDocument.description(in: legacy, isStreaming: true) == nil)
    }

    @Test
    func `replies are never errors`() {
        #expect(ReplyErrorDocument.description(in: "Here is the plan.") == nil)
        #expect(ReplyErrorDocument.description(in: "```\nlet x = 1\n```") == nil)
        #expect(ReplyErrorDocument.description(in: "```swift\nlet x = 1") == nil)
        #expect(ReplyErrorDocument.description(in: "```error\n") == nil)
    }

    @Test
    @MainActor
    func `error row line folds the description onto one line`() {
        #expect(ErrorMessageView.line(of: "Bad request\n\n  details:\tnone ") == "Bad request details: none")
    }

    @Test
    @MainActor
    func `error details popover stays a popover in compact width`() {
        let source = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 20))
        let controller = ErrorDetailController(details: "Invalid API key.", sourceView: source)
        #expect(controller.modalPresentationStyle == .popover)
        let presentation = controller.popoverPresentationController
        #expect(presentation != nil)
        if let presentation {
            let compact = UITraitCollection(horizontalSizeClass: .compact)
            #expect(controller.adaptivePresentationStyle(for: presentation, traitCollection: compact) == .none)
        }
        #expect(controller.preferredContentSize.width == ErrorDetailController.width)
        let long = String(repeating: "A long error line. ", count: 400)
        let size = ErrorDetailController.contentSize(for: long, width: ErrorDetailController.width)
        #expect(size.height <= ErrorDetailController.maximumTextHeight + 100)
    }

    @Test
    @MainActor
    func `failed turn shows as an error row`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Hello")
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: ReplyErrorDocument.document(for: "Unauthorized (401)"))
            }

            let listView = MessageListView()
            listView.session = session
            for isExecuting in [false, true] {
                let entries = listView.entries(from: session.messages, isExecuting: isExecuting)
                    .filter { if case .hint = $0 { false } else { true } }
                guard entries.count == 2, case let .error(_, _, description) = entries[1] else {
                    Issue.record("unexpected entries: \(entries.map(\.id))")
                    return
                }
                #expect(description == "Unauthorized (401)")
            }
        }
    }

    @Test
    @MainActor
    func `reply streaming a bare fence stays a reply`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Write code")
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: "```\nlet x = 1")
            }

            let listView = MessageListView()
            listView.session = session
            let entries = listView.entries(from: session.messages, isExecuting: true)
                .filter { if case .hint = $0 { false } else { true } }
            guard entries.count == 2, case .aiContent = entries[1] else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
        }
    }

    func withTemporarySession(
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Error Row \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }
}

@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct MessageListActivitySummaryTests {
    @Test
    @MainActor
    func `thoughts and tool calls between replies fold into one summary`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Plan a trip")
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Check campgrounds first.")
                $0.update(\.thinkingDuration, to: 6)
                // What the session puts in a reply that only thought.
                $0.update(\.document, to: String(localized: "Empty message."))
            }
            _ = session.appendNewMessage(role: .toolHint) {
                $0.update(\.toolStatus, to: .init(name: "Search Campgrounds", state: 1, message: "Found 4."))
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Write the plan.")
                $0.update(\.thinkingDuration, to: 5)
                $0.update(\.document, to: "Here is the plan.")
            }

            let listView = MessageListView()
            listView.session = session
            let entries = listView.entries(from: session.messages, isExecuting: false)
                .filter { if case .hint = $0 { false } else { true } }

            #expect(entries.count == 3)
            guard entries.count == 3,
                  case .userContent = entries[0],
                  case let .activity(summary) = entries[1],
                  case let .aiContent(_, reply) = entries[2]
            else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
            #expect(summary.steps.count == 3)
            #expect(summary.tools == 1)
            #expect(summary.seconds == 11)
            #expect(!summary.isRunning)
            #expect(summary.title == String(localized: "Thought for \(11) seconds and called 1 tool"))
            #expect(reply.content == "Here is the plan.")
        }
    }

    @Test
    @MainActor
    func `the last summary runs while the session executes`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Look it up")
            }
            _ = session.appendNewMessage(role: .toolHint) {
                $0.update(\.toolStatus, to: .init(name: "Search", state: 0, message: ""))
            }

            let listView = MessageListView()
            listView.session = session
            let summaries = listView.entries(from: session.messages, isExecuting: true).compactMap {
                if case let .activity(summary) = $0 { summary } else { nil }
            }

            #expect(summaries.count == 1)
            #expect(summaries.first?.isRunning == true)
            #expect(summaries.first?.title == String(localized: "Executing tool…"))
            #expect(summaries.first?.banner == "Search")
        }
    }

    @Test
    @MainActor
    func `a running summary drops the banner once its calls finish`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Look it up")
            }
            _ = session.appendNewMessage(role: .toolHint) {
                $0.update(\.toolStatus, to: .init(name: "Search", state: 1, message: "Found 4."))
            }

            let listView = MessageListView()
            listView.session = session
            let summaries = listView.entries(from: session.messages, isExecuting: true).compactMap {
                if case let .activity(summary) = $0 { summary } else { nil }
            }

            #expect(summaries.count == 1)
            #expect(summaries.first?.isRunning == true)
            #expect(summaries.first?.title == String(localized: "Thinking…"))
            #expect(summaries.first?.banner == nil)
        }
    }
}

private extension MessageListActivitySummaryTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Activity Summary \(UUID().uuidString.prefix(8))")
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

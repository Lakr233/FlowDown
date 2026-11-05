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
    func `thinking before and after tool calls folds into one summary without the placeholder`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Any jailbreak news?")
            }
            // What a round that thought and then called tools leaves behind.
            let thought = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Search first.")
                $0.update(\.thinkingDuration, to: 3)
                $0.update(\.document, to: String(localized: "Thinking finished without output any content."))
            }
            session.markDocumentAsPlaceholder(thought)
            for name in ["Search", "Read Page"] {
                _ = session.appendNewMessage(role: .toolHint) {
                    $0.update(\.toolStatus, to: .init(name: name, state: 1, message: "Done."))
                }
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Summarize.")
                $0.update(\.thinkingDuration, to: 2)
                $0.update(\.document, to: "Here is the news.")
            }

            let entries = entriesWithoutDates(session)
            guard entries.count == 3,
                  case .userContent = entries[0],
                  case let .activity(summary) = entries[1],
                  case let .aiContent(_, reply) = entries[2]
            else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
            #expect(summary.steps.count == 4)
            #expect(summary.tools == 2)
            #expect(summary.title == String(localized: "Thought for \(5) seconds and called \(2) tools"))
            #expect(reply.content == "Here is the news.")
        }
    }

    @Test
    @MainActor
    func `a reply cut off mid-reasoning shows only a finished summary`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Prove it")
            }
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Let n be…")
                $0.update(\.thinkingDuration, to: 4)
            }
            // What a cancelled or failed stream does before the session stops.
            session.finalizeInterruptedReasoning()
            _ = session.appendNewMessage(role: .hint) {
                $0.update(\.document, to: "Cancelled.")
            }

            let entries = entriesWithoutDates(session)
            guard entries.count == 3,
                  case .userContent = entries[0],
                  case let .activity(summary) = entries[1],
                  case .hint = entries[2]
            else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
            #expect(!summary.isRunning)
            #expect(summary.title == String(localized: "Thought for \(4) seconds"))
        }
    }

    @Test
    @MainActor
    func `a reply that only thought shows only the summary`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Hmm")
            }
            // A round with reasoning, no text and no tool calls is not marked.
            let thought = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "Nothing to add.")
                $0.update(\.thinkingDuration, to: 2)
                $0.update(\.document, to: String(localized: "Thinking finished without output any content."))
            }

            let entries = entriesWithoutDates(session)
            guard entries.count == 2,
                  case .userContent = entries[0],
                  case let .activity(summary) = entries[1]
            else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
            #expect(!summary.isRunning)
            #expect(summary.steps == [.thought(thought.objectId, text: "Nothing to add.")])
            #expect(summary.title == String(localized: "Thought for \(2) seconds"))
        }
    }

    @Test
    @MainActor
    func `placeholders saved in any language fold into the summary`() async throws {
        // Replies keep the language the app ran in when they were saved.
        let saved = [
            "思考已完成，但没有输出任何内容。",
            "Thinking finished without output any content.",
            "Leere Nachricht.",
            "空消息。",
        ]
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Look it up")
            }
            for placeholder in saved {
                _ = session.appendNewMessage(role: .assistant) {
                    $0.update(\.reasoningContent, to: "Thinking.")
                    $0.update(\.thinkingDuration, to: 1)
                    $0.update(\.document, to: placeholder)
                }
                _ = session.appendNewMessage(role: .toolHint) {
                    $0.update(\.toolStatus, to: .init(name: "Search", state: 1, message: "Done."))
                }
            }

            let entries = entriesWithoutDates(session)
            guard entries.count == 2,
                  case .userContent = entries[0],
                  case let .activity(summary) = entries[1]
            else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
                return
            }
            #expect(summary.steps.count == saved.count * 2)
            #expect(summary.title == String(localized: "Thought for \(4) seconds and called \(4) tools"))
        }
    }

    @Test
    @MainActor
    func `a reply without reasoning keeps text that reads like a placeholder`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Say it")
            }
            // Without reasoning the text is the model's own answer.
            _ = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: "Empty message.")
            }

            let entries = entriesWithoutDates(session)
            #expect(entries.count == 2)
            if case let .aiContent(_, reply)? = entries.last {
                #expect(reply.content == "Empty message.")
            } else {
                Issue.record("unexpected entries: \(entries.map(\.id))")
            }
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
    func entriesWithoutDates(_ session: ConversationSession) -> [MessageListView.Entry] {
        let listView = MessageListView()
        listView.session = session
        return listView.entries(from: session.messages, isExecuting: false)
            .filter { if case let .hint(id, _) = $0 { !id.hasPrefix("date.") } else { true } }
    }

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

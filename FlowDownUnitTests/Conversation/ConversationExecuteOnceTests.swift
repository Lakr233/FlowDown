//
//  ConversationExecuteOnceTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationExecuteOnceTests {
    @Test
    @MainActor
    func cancelBeforeFirstToken_throwsUserCancellation() async throws {
        try await withTemporarySession { _, session in
            let service = ChatServiceSpy(streamHandler: { _ in
                AnyAsyncSequence(AsyncStream<ChatResponseChunk> { continuation in
                    // Stays silent well past the moment the round is cancelled.
                    Task {
                        try? await Task.sleep(for: .seconds(10))
                        continuation.finish()
                    }
                })
            })
            try await withChatService(service) {
                let listView = MessageListView()
                let round = Task { @MainActor () -> Error? in
                    var requestMessages: [ChatRequestBody.Message] = [.user(content: .text("Hello"))]
                    do {
                        _ = try await session.doMainInferenceOnce(
                            listView,
                            "unit-test-model",
                            &requestMessages,
                            nil,
                            false,
                            false,
                        )
                        return nil
                    } catch {
                        return error
                    }
                }

                try await waitUntil { !service.receivedBodies.isEmpty }
                round.cancel()
                let error = await round.value

                #expect(error is InferenceUserCancellationError)
            }
        }
    }

    @Test
    @MainActor
    func reasoningThenToolCall_sendsNoPlaceholderAsAssistantContent() async throws {
        try await withTemporarySession { _, session in
            let reasoning = "Checking the forecast first."
            let service = ChatServiceSpy(streamHandler: { _ in
                AnyAsyncSequence(AsyncStream<ChatResponseChunk> { continuation in
                    continuation.yield(.reasoning(reasoning))
                    continuation.yield(.tool(ToolRequest(name: "unit_test_missing_tool", args: "{}")))
                    continuation.finish()
                })
            })
            try await withChatService(service) {
                let listView = MessageListView()
                var requestMessages: [ChatRequestBody.Message] = [.user(content: .text("Weather?"))]
                // The tool cannot run here, so the round throws once it has
                // recorded the assistant turn.
                var didThrow = false
                do {
                    _ = try await session.doMainInferenceOnce(
                        listView,
                        "unit-test-model",
                        &requestMessages,
                        nil,
                        true,
                        false,
                    )
                } catch {
                    didThrow = true
                }
                #expect(didThrow)

                guard case let .assistant(content, toolCalls, sentReasoning)? = requestMessages.last else {
                    Issue.record("expected the round to append the assistant tool-call turn")
                    return
                }
                let sentAnyContent = content != nil
                #expect(!sentAnyContent)
                #expect(toolCalls?.count == 1)
                #expect(sentReasoning == reasoning)

                guard let assistant = session.messages.last(where: { $0.role == .assistant }) else {
                    Issue.record("expected the round to keep its assistant message")
                    return
                }
                // The UI keeps its placeholder; only the requests drop it.
                #expect(!assistant.document.isEmpty)

                // No tool row follows yet, so nothing would carry the tool
                // call; the placeholder text keeps the turn from going out
                // with neither content nor tool calls.
                let orphaned = await assistantTurns(replaying: session)
                #expect(orphaned == [
                    AssistantTurn(content: assistant.document, toolCallCount: 0, reasoning: reasoning),
                ])

                let toolRow = session.appendNewMessage(role: .toolHint) {
                    $0.update(
                        \.toolStatus,
                        to: Message.ToolStatus(name: "unit_test_missing_tool", state: 1, message: "Sunny")
                    )
                }
                session.encodeToolRequestAndAttachToToolMessage(
                    ToolRequest(name: "unit_test_missing_tool", args: "{}"),
                    message: toolRow,
                )

                // The replayed tool call merges into this turn, which then
                // carries no text at all.
                let merged = await assistantTurns(replaying: session)
                #expect(merged == [
                    AssistantTurn(content: nil, toolCallCount: 1, reasoning: reasoning),
                ])

                assistant.update(\.document, to: "Edited answer")
                let edited = await assistantTurns(replaying: session)
                #expect(edited == [
                    AssistantTurn(content: "Edited answer", toolCallCount: 1, reasoning: reasoning),
                ])
            }
        }
    }

    @Test
    @MainActor
    func reasoningPlaceholderFollowedByHint_replaysItsText() async throws {
        try await withTemporarySession { _, session in
            // Terminate after the tool-call chunk: the cancellation hint
            // lands where the tool row would have gone.
            let reasoning = "Checking the forecast first."
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Weather?")
            }
            let assistant = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: reasoning)
                $0.update(\.document, to: "Thinking finished without output any content.")
            }
            session.markDocumentAsPlaceholder(assistant)
            session.appendNewMessage(role: .hint) {
                $0.update(\.document, to: "User cancelled the operation.")
            }
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Try again.")
            }

            let replayed = await assistantTurns(replaying: session)
            #expect(replayed == [
                AssistantTurn(content: assistant.document, toolCallCount: 0, reasoning: reasoning),
            ])
        }
    }
}

private extension ConversationExecuteOnceTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (Conversation, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Execute Once Tests \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(conversation, session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }

    struct AssistantTurn: Equatable {
        let content: String?
        let toolCallCount: Int
        let reasoning: String?
    }

    /// Replays the session as a request sees it, with adjacent assistant
    /// turns merged into one, and returns those assistant turns.
    @MainActor
    func assistantTurns(replaying session: ConversationSession) async -> [AssistantTurn] {
        var replayed: [ChatRequestBody.Message] = []
        await session.buildInitialRequestMessages(&replayed, [])
        return ChatRequest.mergeAssistantMessages(replayed).compactMap { message -> AssistantTurn? in
            guard case let .assistant(content, toolCalls, reasoning) = message else { return nil }
            let text: String? = switch content {
            case let .text(value)?: value
            case let .parts(parts)?: parts.joined(separator: "\n")
            case nil: nil
            }
            return AssistantTurn(content: text, toolCallCount: toolCalls?.count ?? 0, reasoning: reasoning)
        }
    }

    @MainActor
    func withChatService(
        _ service: ChatServiceSpy,
        _ body: @MainActor () async throws -> Void,
    ) async throws {
        let manager = ModelManager.shared
        let originalFactory = manager.chatServiceFactory
        manager.chatServiceFactory = { _, _ in service }
        defer { manager.chatServiceFactory = originalFactory }
        try await body()
    }

    @MainActor
    func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw NSError(
            domain: "ConversationExecuteOnceTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition."],
        )
    }
}

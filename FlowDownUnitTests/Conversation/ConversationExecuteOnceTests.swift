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
                let round = Task { @MainActor () -> Error? in
                    var requestMessages: [ChatRequestBody.Message] = [.user(content: .text("Hello"))]
                    do {
                        _ = try await session.doMainInferenceOnce(
                            "unit-test-model",
                            &requestMessages,
                            .empty,
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
    func reasoningThenUnknownToolCall_reportsToModelWithoutPlaceholder() async throws {
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
                var requestMessages: [ChatRequestBody.Message] = [.user(content: .text("Weather?"))]
                // Tool calls run inside a live turn; without one the round
                // reads as cancelled before the first call.
                session.currentTask = Task {}
                defer { session.currentTask = nil }
                // No offered tool answers to the name: the model reads that as
                // the call's result, and the turn goes on.
                let ranTools = try await session.doMainInferenceOnce(
                    "unit-test-model",
                    &requestMessages,
                    .empty,
                    true,
                    false,
                )
                #expect(ranTools)

                guard requestMessages.count == 3,
                      case let .assistant(content, toolCalls, sentReasoning) = requestMessages[1],
                      case let .tool(result, toolCallID) = requestMessages[2]
                else {
                    Issue.record("expected the assistant tool-call turn followed by its result")
                    return
                }
                let sentAnyContent = content != nil
                #expect(!sentAnyContent)
                #expect(toolCalls?.count == 1)
                #expect(sentReasoning == reasoning)
                #expect(toolCallID == toolCalls?.first?.id)
                guard case let .text(resultText) = result else {
                    Issue.record("expected a text result")
                    return
                }
                #expect(resultText.contains("unit_test_missing_tool"))

                guard let assistant = session.messages.last(where: { $0.role == .assistant }),
                      let toolRow = session.messages.last(where: { $0.role == .toolHint })
                else {
                    Issue.record("expected the round to keep its assistant message and a tool row")
                    return
                }
                // The UI keeps its placeholder; only the requests drop it.
                #expect(!assistant.document.isEmpty)
                #expect(toolRow.toolStatus.state == ToolCallState.failed)

                // The replayed tool call merges into this turn, which then
                // carries no text at all.
                let merged = await assistantTurns(replaying: session)
                #expect(merged == [
                    AssistantTurn(content: nil, toolCallCount: 1, reasoning: reasoning),
                ])

                // Without the tool row nothing carries the tool call; the
                // placeholder text keeps the turn from going out with neither
                // content nor tool calls.
                session.discard(messageIdentifier: toolRow.objectId)
                let orphaned = await assistantTurns(replaying: session)
                #expect(orphaned == [
                    AssistantTurn(content: assistant.document, toolCallCount: 0, reasoning: reasoning),
                ])

                assistant.update(\.document, to: "Edited answer")
                let edited = await assistantTurns(replaying: session)
                #expect(edited == [
                    AssistantTurn(content: "Edited answer", toolCallCount: 0, reasoning: reasoning),
                ])
            }
        }
    }

    @Test
    @MainActor
    func toolCallExtraFields_echoInFollowUpButStayOutOfStorage() async throws {
        let extraFields: [String: AnyCodingValue] = [
            "extra_content": ["google": ["thought_signature": "unit-test-signature"]],
        ]
        let (signedCall, signedRow) = try await followUpToolCall(
            for: ToolRequest(id: "call_signed", name: "unit_test_missing_tool", args: "{}", extraFields: extraFields),
        )
        #expect(signedCall.extraFields == extraFields)
        let signedJSON = try encodedToolCall(signedCall)
        let extraContent = signedJSON["extra_content"] as? [String: Any]
        let google = extraContent?["google"] as? [String: Any]
        #expect(google?["thought_signature"] as? String == "unit-test-signature")
        // The stored tool request keeps its format; the signature is not saved.
        #expect(signedRow == ["args", "id", "name"])

        let (plainCall, plainRow) = try await followUpToolCall(
            for: ToolRequest(id: "call_plain", name: "unit_test_missing_tool", args: "{}"),
        )
        #expect(plainCall.extraFields == nil)
        let plainJSON = try encodedToolCall(plainCall)
        #expect(Set(plainJSON.keys) == ["id", "type", "function"])
        #expect(plainRow == ["args", "id", "name"])
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

    @Test
    @MainActor
    func webSearchRowWithoutToolRequest_keepsLaterTurns() async throws {
        try await withTemporarySession { _, session in
            // Rows from the retired pre-action web search carry no tool
            // request; they must not cut off the history that follows.
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "First question")
            }
            session.appendNewMessage(role: .webSearch)
            session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: "First answer")
            }
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Second question")
            }

            var replayed: [ChatRequestBody.Message] = []
            await session.buildInitialRequestMessages(&replayed, [])
            let texts = replayed.compactMap { message -> String? in
                switch message {
                case let .user(.text(value), _): value
                case let .assistant(.text(value)?, _, _): value
                default: nil
                }
            }
            #expect(texts == ["First question", "First answer", "Second question"])
        }
    }

    @Test
    @MainActor
    func retryAfterToolAttachments_targetsTheUserPrompt() async throws {
        try await withTemporarySession { _, session in
            let question = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Take a screenshot")
            }
            session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: "Calling the tool.")
            }
            session.appendNewMessage(role: .toolHint)
            let holder = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Collected 1 attachments from tool Screenshot.")
            }
            session.markAsAttachmentHolder(holder)
            let answer = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: "Here is the screenshot.")
            }

            #expect(session.nearestUserMessage(beforeOrEqual: answer.objectId)?.objectId == question.objectId)
            #expect(session.nearestUserMessage(beforeOrEqual: holder.objectId)?.objectId == question.objectId)
        }
    }

    @Test
    @MainActor
    func summaryFinishingAfterDeletion_isNotSaved() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Summary Tests \(UUID().uuidString.prefix(8))")
        }
        let conversationID = conversation.id
        let session = ConversationSessionManager.shared.session(for: conversationID)
        for index in 1 ... 3 {
            session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Question \(index)")
            }
        }
        let messages = session.messages

        // The user deletes the conversation while the summary is generated.
        let service = ChatServiceSpy(chatHandler: { _ in
            await MainActor.run {
                ConversationManager.shared.deleteConversation(identifier: conversationID)
            }
            return ChatResponse(reasoning: "", text: "SUMMARY: Three questions.\nTOPICS: tests", images: [], tools: [])
        })
        try await withChatService(service) {
            await ConversationSummarizer.shared.summarizeIfNeeded(
                conversationId: conversationID,
                messages: messages,
                using: "unit-test-model",
            )
        }

        #expect(!service.receivedBodies.isEmpty)
        #expect(try Storage.db().getSummary(forConversation: conversationID) == nil)
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

    /// Runs one round whose model emits `request`, then returns the tool
    /// call sent in the follow-up and the keys of the stored tool request.
    @MainActor
    func followUpToolCall(
        for request: ToolRequest,
    ) async throws -> (ChatRequestBody.Message.ToolCall, Set<String>) {
        var result: (ChatRequestBody.Message.ToolCall, Set<String>)?
        try await withTemporarySession { _, session in
            let service = ChatServiceSpy(streamHandler: { _ in
                AnyAsyncSequence(AsyncStream<ChatResponseChunk> { continuation in
                    continuation.yield(.tool(request))
                    continuation.finish()
                })
            })
            try await withChatService(service) {
                var requestMessages: [ChatRequestBody.Message] = [.user(content: .text("Weather?"))]
                session.currentTask = Task {}
                defer { session.currentTask = nil }
                _ = try await session.doMainInferenceOnce(
                    "unit-test-model",
                    &requestMessages,
                    .empty,
                    true,
                    false,
                )
                guard requestMessages.count == 3,
                      case let .assistant(_, toolCalls, _) = requestMessages[1],
                      let call = toolCalls?.first,
                      let toolRow = session.messages.last(where: { $0.role == .toolHint }),
                      let metadata = toolRow.metadata,
                      let object = try JSONSerialization.jsonObject(with: metadata) as? [String: Any],
                      let stored = object["tool_request"] as? [String: Any]
                else {
                    Issue.record("expected the assistant tool-call turn and a stored tool row")
                    return
                }
                result = (call, Set(stored.keys))
            }
        }
        return try #require(result)
    }

    func encodedToolCall(_ call: ChatRequestBody.Message.ToolCall) throws -> [String: Any] {
        let data = try JSONEncoder().encode(call)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

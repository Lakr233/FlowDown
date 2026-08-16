//
//  ConversationTrimTests.swift
//  FlowDownUnitTests
//
//  Created by GPT-5 Codex on 8/16/26.
//

@preconcurrency @testable import FlowDown
import ChatClientKit
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationTrimTests {
    @Test
    @MainActor
    func `trim keeps the current user message when older turns overflow the context`() async throws {
        try await withTemporarySession { _, session in
            let filler = String(repeating: "previous conversation content. ", count: 400)
            var requestMessages: [ChatRequestBody.Message] = [
                .system(content: .text("You are a helpful assistant.")),
                .user(content: .text(filler)),
                .assistant(content: .text(filler)),
                .user(content: .text("What is the capital of France?")),
            ]

            let trimmed = try await runOffMain {
                try session.removeOutOfContextContents(
                    &requestMessages,
                    nil,
                    512,
                    preservesReasoning: false,
                )
            }

            #expect(trimmed)
            #expect(requestMessages.count == 2)
            guard case .system = requestMessages[0] else {
                Issue.record("expected the system message to survive the trim")
                return
            }
            guard case let .user(content, _) = requestMessages[1],
                  case let .text(text) = content
            else {
                Issue.record("expected the final user message to survive the trim")
                return
            }
            #expect(text == "What is the capital of France?")
        }
    }

    @Test
    @MainActor
    func `trim throws rather than dropping the user message when nothing else can be evicted`() async throws {
        try await withTemporarySession { _, session in
            let filler = String(repeating: "system prompt segment. ", count: 400)
            var requestMessages: [ChatRequestBody.Message] = [
                .system(content: .text(filler)),
                .user(content: .text("Hello")),
            ]

            let threw = await runOffMain {
                do {
                    _ = try session.removeOutOfContextContents(
                        &requestMessages,
                        nil,
                        64,
                        preservesReasoning: false,
                    )
                    return false
                } catch {
                    return true
                }
            }

            #expect(threw)
            #expect(requestMessages.count == 2)
            guard case .user = requestMessages[1] else {
                Issue.record("the failed trim must leave the user message in place")
                return
            }
        }
    }

    @Test
    func `reasoning is excluded from the token estimate unless the model preserves thinking`() async throws {
        let reasoning = String(repeating: "let me think about this step by step. ", count: 200)
        let messages: [ChatRequestBody.Message] = [
            .assistant(content: .text("short answer"), reasoning: reasoning),
        ]

        let withReasoning = try await runOffMain {
            ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: messages,
                tools: [],
                includingReasoning: true,
            )
        }
        let withoutReasoning = try await runOffMain {
            ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: messages,
                tools: [],
                includingReasoning: false,
            )
        }

        #expect(withReasoning > withoutReasoning + 100)
    }
}

private extension ConversationTrimTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (Conversation, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Trim Tests \(UUID().uuidString.prefix(8))")
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

    /// The token estimator asserts it runs off the main thread.
    func runOffMain<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T,
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: .init(catching: work))
            }
        }
    }
}

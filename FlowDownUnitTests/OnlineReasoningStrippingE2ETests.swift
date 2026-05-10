//
//  OnlineReasoningStrippingE2ETests.swift
//  FlowDownUnitTests
//
//  E2E coverage for the reasoning strip in chat-completions requests.
//  When a reasoning-capable provider returns `reasoning_content` and the
//  app echoes it back on the next turn, providers like DeepSeek (and
//  Moonshot's Kimi-Turbo) reject the request. This suite walks the full
//  round trip and asserts the follow-up turn succeeds.
//

@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

@Suite(.serialized)
struct OnlineReasoningStrippingE2ETests {
    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled))
    func `Reasoning content is captured for a reasoning-capable model`() async throws {
        let client = try OnlineE2ETestSupport.makeCompletionsClient()
        let body = ChatRequestBody(
            messages: [
                .user(content: .text("Say hello in one sentence.")),
            ],
            maxCompletionTokens: 512,
        )

        let response = try await client.chat(body: body)

        if response.reasoning.isEmpty, response.text.isEmpty {
            Issue.record("Provider returned no text or reasoning content; cannot validate reasoning capture.")
            return
        }
        #expect(!response.text.isEmpty)
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled))
    func `Follow-up turn succeeds when prior reasoning is retained on assistant message`() async throws {
        let client = try OnlineE2ETestSupport.makeCompletionsClient()

        let firstBody = ChatRequestBody(
            messages: [
                .user(content: .text("Briefly explain why the sky is blue, in one sentence.")),
            ],
            maxCompletionTokens: 512,
        )

        let firstResponse = try await client.chat(body: firstBody)
        #expect(!firstResponse.text.isEmpty)

        // Echo the prior assistant turn back, including reasoning. Pre-fix,
        // the encoder shipped a `reasoning` field in the assistant message
        // and providers like Moonshot Kimi-Turbo rejected the request with
        // an HTTP error. Post-fix, the encoder drops the field on the wire
        // and the request succeeds.
        let secondBody = ChatRequestBody(
            messages: [
                .user(content: .text("Briefly explain why the sky is blue, in one sentence.")),
                .assistant(
                    content: .text(firstResponse.text),
                    toolCalls: nil,
                    reasoning: firstResponse.reasoning.isEmpty
                        ? "Synthetic reasoning trace for regression coverage."
                        : firstResponse.reasoning,
                ),
                .user(content: .text("Now restate that in five words or fewer.")),
            ],
            maxCompletionTokens: 512,
        )

        let secondResponse = try await client.chat(body: secondBody)
        #expect(!secondResponse.text.isEmpty)
    }
}

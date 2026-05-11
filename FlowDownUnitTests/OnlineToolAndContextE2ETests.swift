@testable import ChatClientKit
@testable import FlowDown
import Foundation
@testable import Storage
import Testing

/// End-to-end coverage that hits both the Chat Completions and Responses APIs
/// against the live backing model. Exercises:
/// - multi-round tool calling (round-trip the tool output back into the model)
/// - second-tool continuation (tool output must drive a follow-up tool call)
/// - multi-turn context recall (prior assistant turn informs later answer)
@Suite(.serialized)
struct OnlineToolAndContextE2ETests {
    static let responseFormats = OnlineE2ETestSupport.responseFormats

    // MARK: Tools

    private var addNumbersTool: ChatRequestBody.Tool {
        .function(
            name: "add_numbers",
            description: "Add two integers and return the sum.",
            parameters: [
                "type": "object",
                "properties": [
                    "a": ["type": "integer"],
                    "b": ["type": "integer"],
                ],
                "required": ["a", "b"],
            ],
            strict: true,
        )
    }

    private var lookupPopulationTool: ChatRequestBody.Tool {
        .function(
            name: "lookup_population",
            description: "Returns the population for a given city name in millions (approximate).",
            parameters: [
                "type": "object",
                "properties": [
                    "city": ["type": "string"],
                ],
                "required": ["city"],
            ],
            strict: true,
        )
    }

    // MARK: Client factory

    private func makeClient(for responseFormat: CloudModel.ResponseFormat) throws -> any ChatService {
        switch responseFormat {
        case .chatCompletions:
            return try OnlineE2ETestSupport.makeCompletionsClient()
        case .responses:
            return try OnlineE2ETestSupport.makeResponsesClient()
        }
    }

    private func collect(
        _ client: any ChatService,
        body: ChatRequestBody,
    ) async throws -> ChatResponse {
        try await retryingTransientErrors {
            let stream = try await client.streamingChat(body: body)
            var chunks: [ChatResponseChunk] = []
            for try await chunk in stream {
                chunks.append(chunk)
            }
            return ChatResponse(chunks: chunks)
        }
    }

    // MARK: Retry helper

    private func retryingTransientErrors<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T,
    ) async throws -> T {
        precondition(maxAttempts > 0)
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, isTransientNetworkError(error) else { throw error }
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        throw lastError ?? CancellationError()
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorResourceUnavailable,
            ].contains(ns.code)
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return isTransientNetworkError(underlying)
        }
        return false
    }

    // MARK: Tests

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineToolAndContextE2ETests.responseFormats)
    func `single round tool call produces final answer with tool output`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let prompt = """
        Use the add_numbers tool exactly once with a=17 and b=25.
        First turn: emit the tool call and stop.
        After the tool result arrives, reply with the final sum and include the number 42.
        """

        let firstResponse = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [addNumbersTool],
            ),
        )

        let toolCall = try #require(firstResponse.tools.first, "Expected a tool call from the model.")
        #expect(toolCall.name == "add_numbers")
        #expect(toolCall.args.contains("\"a\""))
        #expect(toolCall.args.contains("\"b\""))

        let finalResponse = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .user(content: .text(prompt)),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: toolCall.id,
                                function: .init(name: toolCall.name, arguments: toolCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("42"), toolCallID: toolCall.id),
                ],
                maxCompletionTokens: 256,
                temperature: 0,
            ),
        )

        let text = finalResponse.text
        #expect(!text.isEmpty, "Expected final assistant text after tool output.")
        #expect(text.contains("42"), "Expected final answer to include the tool result.")
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineToolAndContextE2ETests.responseFormats)
    func `sequential tool calls chain through two rounds`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let prompt = """
        You have two tools: lookup_population(city) and add_numbers(a, b).
        1. First, call lookup_population for "Tokyo" and stop.
        2. When the population result arrives, call lookup_population for "Osaka" and stop.
        3. After both values are known, call add_numbers with a=<tokyo> b=<osaka> and stop.
        4. Finally, report the combined population in millions, including the exact total you receive from add_numbers.
        Always call exactly one tool per turn.
        """

        // Round 1: expect a call for Tokyo.
        let round1 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [lookupPopulationTool, addNumbersTool],
            ),
        )
        let tokyoCall = try #require(round1.tools.first, "Expected a first-round tool call.")
        #expect(tokyoCall.name == "lookup_population")
        #expect(tokyoCall.args.lowercased().contains("tokyo"))

        // Round 2: feed Tokyo=14, expect a call for Osaka.
        let round2 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .user(content: .text(prompt)),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: tokyoCall.id,
                                function: .init(name: tokyoCall.name, arguments: tokyoCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("14"), toolCallID: tokyoCall.id),
                ],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [lookupPopulationTool, addNumbersTool],
            ),
        )
        let osakaCall = try #require(round2.tools.first, "Expected a second-round tool call.")
        #expect(osakaCall.name == "lookup_population")
        #expect(osakaCall.args.lowercased().contains("osaka"))

        // Round 3: feed Osaka=3, expect a call to add_numbers.
        let round3 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .user(content: .text(prompt)),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: tokyoCall.id,
                                function: .init(name: tokyoCall.name, arguments: tokyoCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("14"), toolCallID: tokyoCall.id),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: osakaCall.id,
                                function: .init(name: osakaCall.name, arguments: osakaCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("3"), toolCallID: osakaCall.id),
                ],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [lookupPopulationTool, addNumbersTool],
            ),
        )
        let addCall = try #require(round3.tools.first, "Expected a third-round tool call.")
        #expect(addCall.name == "add_numbers")

        // Round 4: feed add result 17, expect the model to incorporate it.
        let round4 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .user(content: .text(prompt)),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: tokyoCall.id,
                                function: .init(name: tokyoCall.name, arguments: tokyoCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("14"), toolCallID: tokyoCall.id),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: osakaCall.id,
                                function: .init(name: osakaCall.name, arguments: osakaCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("3"), toolCallID: osakaCall.id),
                    .assistant(
                        content: nil,
                        toolCalls: [
                            .init(
                                id: addCall.id,
                                function: .init(name: addCall.name, arguments: addCall.args),
                            ),
                        ],
                    ),
                    .tool(content: .text("17"), toolCallID: addCall.id),
                ],
                maxCompletionTokens: 512,
                temperature: 0,
                tools: [lookupPopulationTool, addNumbersTool],
            ),
        )

        let text = round4.text
        #expect(!text.isEmpty, "Expected the model to produce a final natural-language answer.")
        #expect(text.contains("17"), "Final answer should cite the add_numbers tool result. Got: \(text)")
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineToolAndContextE2ETests.responseFormats)
    func `multi turn conversation recalls earlier user facts`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)

        // Turn 1: establish facts.
        let turn1 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .system(content: .text("You answer concisely and truthfully, reusing prior facts.")),
                    .user(content: .text("Hi! Remember two things: my name is Priya and my favorite drink is oolong tea. Reply with a short acknowledgment.")),
                ],
                maxCompletionTokens: 128,
                temperature: 0,
            ),
        )
        #expect(!turn1.text.isEmpty, "Expected acknowledgment on first turn.")

        // Turn 2: recall one fact.
        let turn2 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .system(content: .text("You answer concisely and truthfully, reusing prior facts.")),
                    .user(content: .text("Hi! Remember two things: my name is Priya and my favorite drink is oolong tea. Reply with a short acknowledgment.")),
                    .assistant(content: .text(turn1.text)),
                    .user(content: .text("What did I tell you my name was? Answer with just the name.")),
                ],
                maxCompletionTokens: 256,
                temperature: 0,
            ),
        )
        #expect(turn2.text.localizedCaseInsensitiveContains("Priya"), "Expected the model to recall the name 'Priya'. Got: \(turn2.text)")

        // Turn 3: recall the second fact — deeper multi-turn history.
        let turn3 = try await collect(
            client,
            body: ChatRequestBody(
                messages: [
                    .system(content: .text("You answer concisely and truthfully, reusing prior facts.")),
                    .user(content: .text("Hi! Remember two things: my name is Priya and my favorite drink is oolong tea. Reply with a short acknowledgment.")),
                    .assistant(content: .text(turn1.text)),
                    .user(content: .text("What did I tell you my name was? Answer with just the name.")),
                    .assistant(content: .text(turn2.text)),
                    .user(content: .text("And what is my favorite drink? Answer with just the drink name.")),
                ],
                maxCompletionTokens: 256,
                temperature: 0,
            ),
        )
        #expect(turn3.text.localizedCaseInsensitiveContains("oolong"), "Expected the model to recall 'oolong tea'. Got: \(turn3.text)")
    }
}

@testable import ChatClientKit
@testable import FlowDown
import Foundation
@testable import Storage
import Testing

@Suite(.serialized)
struct OnlineCacheUsageE2ETests {
    @Test
    func `chat completions usage decoder reads input and output cache fields`() throws {
        let payload = """
        {
          "usage": {
            "prompt_tokens": 1200,
            "completion_tokens": 42,
            "total_tokens": 1242,
            "prompt_tokens_details": {
              "cached_tokens": 1024
            },
            "completion_tokens_details": {
              "cached_tokens": 8
            }
          }
        }
        """

        let response = try JSONDecoder().decode(
            ChatCompletionsUsageProbeResponse.self,
            from: Data(payload.utf8),
        )

        #expect(response.usage.cachedInputTokens == 1024)
        #expect(response.usage.cachedOutputTokens == 8)
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled(for: .chatCompletions)), .timeLimit(.minutes(2)))
    func `chat completions reports cached input tokens after repeated long prefix`() async throws {
        let body = ChatRequestBody(
            messages: [
                .system(content: .text(Self.cacheablePrefix())),
                .user(content: .text("Reply with OK.")),
            ],
            maxCompletionTokens: 1,
            temperature: 0,
        )

        var usages: [ChatCompletionsUsageProbeResponse.Usage] = []
        for attempt in 1 ... 5 {
            let usage = try await fetchUsage(body: body)
            usages.append(usage)
            if usage.cachedInputTokens > 0 {
                break
            }
            try await Task.sleep(for: .seconds(Double(attempt)))
        }

        let firstUsage = try #require(usages.first)
        let cacheHit = try #require(
            usages.first { $0.cachedInputTokens > 0 },
            "Expected a repeated long prompt to report cached input tokens. Usages: \(usages)",
        )

        #expect(firstUsage.promptTokens == cacheHit.promptTokens)
        #expect(cacheHit.cachedInputTokens < cacheHit.promptTokens)
        #expect(cacheHit.completionTokens > 0)
    }

    private func fetchUsage(body: ChatRequestBody) async throws -> ChatCompletionsUsageProbeResponse.Usage {
        let client = try OnlineE2ETestSupport.makeCompletionsClient()
        let request = try client.makeURLRequest(body: client.resolve(body: body, stream: false))
        let (data, response) = try await URLSession.shared.data(for: request)
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ..< 300).contains(httpResponse.statusCode)
        {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            throw NSError(
                domain: "OnlineCacheUsageE2ETests",
                code: httpResponse.statusCode,
                userInfo: [
                    NSLocalizedDescriptionKey: "HTTP \(httpResponse.statusCode): \(body)",
                ],
            )
        }

        return try JSONDecoder().decode(ChatCompletionsUsageProbeResponse.self, from: data).usage
    }

    private static func cacheablePrefix() -> String {
        let probeID = UUID().uuidString
        let repeated = (1 ... 2500)
            .map { "flowdown-cache-probe-\(probeID)-\($0)" }
            .joined(separator: " ")
        return """
        You are a cache usage probe. The following deterministic prefix must be kept identical across repeated requests.
        \(repeated)
        """
    }
}

private struct ChatCompletionsUsageProbeResponse: Decodable {
    let usage: Usage

    struct Usage: Decodable, CustomStringConvertible {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        let promptTokensDetails: TokenDetails?
        let completionTokensDetails: TokenDetails?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
            case promptTokensDetails = "prompt_tokens_details"
            case completionTokensDetails = "completion_tokens_details"
        }

        var cachedInputTokens: Int {
            promptTokensDetails?.cachedTokens ?? 0
        }

        var cachedOutputTokens: Int {
            completionTokensDetails?.cachedTokens ?? 0
        }

        var description: String {
            "prompt=\(promptTokens), completion=\(completionTokens), total=\(totalTokens), cachedInput=\(cachedInputTokens), cachedOutput=\(cachedOutputTokens)"
        }
    }

    struct TokenDetails: Decodable {
        let cachedTokens: Int?

        enum CodingKeys: String, CodingKey {
            case cachedTokens = "cached_tokens"
        }
    }
}

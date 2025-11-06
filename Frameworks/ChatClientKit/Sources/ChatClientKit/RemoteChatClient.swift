//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import RegexBuilder
import ServerEvent
import Tokenizers

open class RemoteChatClient: ChatService {
    private let session = URLSession.shared

    /// The ID of the model to use.
    ///
    /// The required section should be in alphabetical order.
    public let model: String
    public var baseURL: String?
    public var apiKey: String?

    /// The format handler for API requests and responses
    public let format: ChatFormatProtocol
    public var debugLogging: Bool = false

    public enum Error: Swift.Error {
        case invalidURL
        case invalidApiKey
        case invalidData
    }

    public var collectedErrors: String?

    public var additionalHeaders: [String: String] = [:]
    public var additionalField: [String: Any] = [:]

    public init(
        model: String,
        format: ChatFormatProtocol,
        baseURL: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:]
    ) {
        self.model = model
        self.format = format
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.additionalHeaders = additionalHeaders
        additionalField = additionalBodyField
    }

    /// Convenience initializer using OpenAI Chat Completion format
    public convenience init(
        model: String,
        baseURL: String? = nil,
        apiKey: String? = nil,
        additionalHeaders: [String: String] = [:],
        additionalBodyField: [String: Any] = [:]
    ) {
        self.init(
            model: model,
            format: OpenAIChatCompletionFormat(),
            baseURL: baseURL,
            apiKey: apiKey,
            additionalHeaders: additionalHeaders,
            additionalBodyField: additionalBodyField
        )
    }

    public func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        var body = body
        body.model = model
        body.stream = false
        body.streamOptions = nil
        let request = try request(for: body, additionalField: additionalField)
        let (data, response) = try await session.data(for: request)
        if debugLogging {
            if let http = response as? HTTPURLResponse {
                print("[RemoteChatClient] Response status: \(http.statusCode)")
                print("[RemoteChatClient] Response headers: \(http.allHeaderFields)")
            }
            if let raw = String(data: data, encoding: .utf8) {
                print("[RemoteChatClient] Raw response (truncated 2k): \(raw.prefix(2048))")
            } else {
                print("[RemoteChatClient] Raw response: <non-utf8 data, \(data.count) bytes>")
            }
        }
        do {
            var response = try format.parseResponse(from: data)
            response.choices = response.choices.map { choice in
                var choice = choice
                choice.message = extractReasoningContent(from: choice.message)
                return choice
            }
            return response
        } catch {
            if let decodedError = format.parseError(from: data) {
                collectedErrors = decodedError.localizedDescription
                throw decodedError
            }
            collectedErrors = error.localizedDescription
            throw error
        }
    }

    private func processReasoningContent(
        _ content: [String],
        _ reasoningContent: [String],
        _ isInsideReasoningContent: inout Bool,
        _ response: inout ChatCompletionChunk
    ) {
        // now we can decode <think> and </think> tag for that purpose
        // transfer all content to buffer, and begin our process
        let bufferContent = content.joined() // 将内容数组合并为单个字符串
        assert(reasoningContent.isEmpty)

        if !isInsideReasoningContent {
            if let range = bufferContent.range(of: REASONING_START_TOKEN) {
                let beforeReasoning = String(bufferContent[..<range.lowerBound])
                    .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                let afterReasoningBegin = String(bufferContent[range.upperBound...])
                    .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                // 检查同一块内容中是否有结束标记
                if let endRange = afterReasoningBegin.range(of: REASONING_END_TOKEN) {
                    // 有开始也有结束标记 - 完整的推理块
                    let reasoningText = String(afterReasoningBegin[..<endRange.lowerBound])
                        .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                    let remainingText = String(afterReasoningBegin[endRange.upperBound...])
                        .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                    // 更新响应数据
                    var delta = [ChatCompletionChunk.Choice.Delta]()
                    if !beforeReasoning.isEmpty {
                        delta.append(.init(content: beforeReasoning))
                    }
                    if !reasoningText.isEmpty {
                        delta.append(.init(reasoningContent: reasoningText))
                    }
                    if !remainingText.isEmpty {
                        delta.append(.init(content: remainingText))
                    }
                    response = .init(choices: delta.map { .init(delta: $0) })
                } else {
                    // 有开始标记但没有结束标记 - 进入推理内容
                    isInsideReasoningContent = true
                    var delta = [ChatCompletionChunk.Choice.Delta]()
                    if !beforeReasoning.isEmpty {
                        delta.append(.init(content: beforeReasoning))
                    }
                    if !afterReasoningBegin.isEmpty {
                        delta.append(.init(reasoningContent: afterReasoningBegin))
                    }
                    response = .init(choices: delta.map { .init(delta: $0) })
                    // 如果刚好在 </think> 前面截断了 那就只有服务器知道要不要 cut 了
                    // UI 上面可以处理一下
                }
            }
        } else {
            // 我们已经在推理内容中，检查是否有结束标记
            if let range = bufferContent.range(of: REASONING_END_TOKEN) {
                // 找到结束标记 - 退出推理模式
                isInsideReasoningContent = false

                let reasoningText = String(bufferContent[..<range.lowerBound])
                    .trimmingCharactersFromEnd(in: .whitespacesAndNewlines)
                let remainingText = String(bufferContent[range.upperBound...])
                    .trimmingCharactersFromStart(in: .whitespacesAndNewlines)

                // 更新响应数据
                response = .init(choices: [
                    .init(delta: .init(reasoningContent: reasoningText)),
                    .init(delta: .init(content: remainingText)),
                ])
            } else {
                // 仍在推理内容中
                response = .init(choices: [.init(delta: .init(
                    reasoningContent: bufferContent
                ))])
            }
        }
    }

    public func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        var body = body
        body.model = model
        body.stream = true

        // streamOptions is not supported when running up on cohere api
        // body.streamOptions = .init(includeUsage: true)
        let request = try request(for: body, additionalField: additionalField)
        logger.info("starting streaming request with \(body.messages.count) messages")

        let stream = AsyncStream<ChatServiceStreamObject> { continuation in
            Task.detached {
                // Extracts or preserves the reasoning content within a `ChoiceMessage`.

                var canDecodeReasoningContent = true
                var isInsideReasoningContent = false
                let toolCallCollector: ToolCallCollector = .init()

                let eventSource = EventSource()
                let dataTask = eventSource.dataTask(for: request)

                for await event in dataTask.events() {
                    switch event {
                    case .open:
                        logger.info("connection was opened.")
                    case let .error(error):
                        logger.error("received an error: \(error)")
                        self.collect(error: error)
                    case let .event(event):
                        if self.debugLogging {
                            print("[RemoteChatClient][SSE] event=\(event.event ?? "message"), id=\(event.id ?? "")")
                            if let d = event.data { print("[RemoteChatClient][SSE] data: \(d)") }
                        }
                        guard let data = event.data?.data(using: .utf8) else {
                            continue
                        }
                        do {
                            guard let parsedResponse = try self.format.parseStreamingChunk(from: data) else {
                                continue
                            }
                            print(parsedResponse)
                            var response = parsedResponse
                            let reasoningContent = [
                                response.choices.map(\.delta).compactMap(\.reasoning),
                                response.choices.map(\.delta).compactMap(\.reasoningContent),
                            ].flatMap(\.self)
                            let content = response.choices.map(\.delta).compactMap(\.content)

                            if canDecodeReasoningContent { canDecodeReasoningContent = reasoningContent.isEmpty }

                            if canDecodeReasoningContent {
                                self.processReasoningContent(content, reasoningContent, &isInsideReasoningContent, &response)
                            }

                            for delta in response.choices {
                                for toolDelta in delta.delta.toolCalls ?? [] {
                                    toolCallCollector.submit(delta: toolDelta)
                                }
                            }

                            continuation.yield(.chatCompletionChunk(chunk: response))
                        } catch {
                            if let text = String(data: data, encoding: .utf8) {
                                logger.log("text content associated with this error \(text)")
                            }
                            self.collect(error: error)
                        }
                        if let decodeError = self.format.parseError(from: data) {
                            self.collect(error: decodeError)
                        }
                    case .closed:
                        logger.info("connection was closed.")
                    }
                }

                toolCallCollector.finalizeCurrentDeltaContent()
                for call in toolCallCollector.pendingRequests {
                    continuation.yield(.tool(call: call))
                }
                continuation.finish()
            }
        }
        return stream.eraseToAnyAsyncSequence()
    }

    private func collect(error: Swift.Error) {
        if let error = error as? EventSourceError {
            switch error {
            case .undefinedConnectionError:
                collectedErrors = String(localized: "Unable to connect to the server.", bundle: .module)
            case let .connectionError(statusCode, response):
                if let decodedError = format.parseError(from: response) {
                    collectedErrors = decodedError.localizedDescription
                } else {
                    collectedErrors = String(localized: "Connection error: \(statusCode)", bundle: .module)
                }
            case .alreadyConsumed:
                assertionFailure()
            }
            return
        }
        collectedErrors = error.localizedDescription
        logger.error("collected error: \(error.localizedDescription)")
    }

    private func request(for body: ChatRequestBody, additionalField: [String: Any] = [:]) throws -> URLRequest {
        guard let baseURL else {
            throw Error.invalidURL
        }
        guard let apiKey else {
            throw Error.invalidApiKey
        }

        let url: URL

        // Prefer explicit endpoint if provided
        if baseURL.hasSuffix("/responses") || baseURL.hasSuffix("/chat/completions") {
            guard let directURL = URL(string: baseURL) else { throw Error.invalidURL }
            url = directURL
        } else {
            // Compose base and apiPath robustly without duplicating /v1
            let base = baseURL.hasSuffix("/") ? String(baseURL.dropLast()) : baseURL
            let apiPath = format.apiPath
            let lowercasedBase = base.lowercased()
            let isChatGPTCodex = lowercasedBase.contains("chatgpt.com") && lowercasedBase.contains("/backend-api/codex")

            if isChatGPTCodex {
                // ChatGPT Codex uses `/backend-api/codex/responses` (no /v1)
                let path = base.hasSuffix("/responses") ? "" : "/responses"
                guard let composed = URL(string: base + path) else { throw Error.invalidURL }
                url = composed
            } else if apiPath.hasPrefix("/v1/"), base.hasSuffix("/v1") {
                let trimmed = String(apiPath.dropFirst(3)) // remove leading "/v1"
                guard let composed = URL(string: base + trimmed) else { throw Error.invalidURL }
                url = composed
            } else {
                let sep = apiPath.hasPrefix("/") ? "" : "/"
                guard let composed = URL(string: base + sep + apiPath) else { throw Error.invalidURL }
                url = composed
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let prepared = try format.prepareRequest(from: body, model: model, additionalFields: additionalField)
        // Sanitize request body by removing fields not needed/unsupported by Codex
        // Fields to drop (snake_case to match wire format):
        // temperature, top_p, max_output_tokens, user, text_formatting, truncation, text, service_tier
        if let obj = try? JSONSerialization.jsonObject(with: prepared) as? [String: Any] {
            var sanitized = obj
            let fieldsToRemove: Set<String> = [
                "temperature",
                "top_p",
                "max_output_tokens",
                "user",
                "text_formatting",
                "truncation",
                "text",
                "service_tier",
            ]
            for key in fieldsToRemove {
                sanitized.removeValue(forKey: key)
            }
            if let data = try? JSONSerialization.data(withJSONObject: sanitized) {
                request.httpBody = data
            } else {
                request.httpBody = prepared
            }
        } else {
            request.httpBody = prepared
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        // Add ChatGPT Codex-specific headers by default if targeting that host
        if let host = url.host?.lowercased(), host.contains("chatgpt.com"), url.absoluteString.contains("/backend-api/codex/") {
            if request.value(forHTTPHeaderField: "OpenAI-Beta") == nil {
                request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
            }
            if request.value(forHTTPHeaderField: "Codex-Task-Type") == nil {
                request.setValue("standard", forHTTPHeaderField: "Codex-Task-Type")
            }
        }

        // additionalHeaders can override default headers including Authorization
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if debugLogging {
            let masked = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { acc, kv in
                let (k, v) = kv
                if k.lowercased() == "authorization" {
                    acc[k] = "Bearer ***masked***"
                } else {
                    acc[k] = v
                }
            }
            print("[RemoteChatClient] Request URL: \(url.absoluteString)")
            print("[RemoteChatClient] Request headers: \(masked)")
            if let body = request.httpBody, let bodyStr = String(data: body, encoding: .utf8) {
                print("[RemoteChatClient] Request body: \(bodyStr)")
            } else if let body = request.httpBody {
                print("[RemoteChatClient] Request body bytes: \(body.count)")
            }
        }

        return request
    }

    /// Extracts or preserves the reasoning content within a `ChoiceMessage`.
    ///
    /// This function inspects the provided `ChoiceMessage` to determine if it already contains
    /// a `reasoningContent` value, indicating compliance with the expected API format. If present,
    /// the original `ChoiceMessage` is returned unchanged. Otherwise, it attempts to extract the text
    /// enclosed within `<think>` and `</think>` tags from the `content` property,
    /// creating a new `ChoiceMessage` with the extracted content assigned to `reasoningContent`.
    ///
    /// - Parameter choice: The `ChoiceMessage` object to process.
    /// - Returns: A `ChoiceMessage` object, either the original if `reasoningContent` exists, or a new one
    ///            with extracted reasoning content if applicable; returns the original if extraction fails.
    private func extractReasoningContent(from choice: ChoiceMessage) -> ChoiceMessage {
        if false
            || choice.reasoning?.isEmpty == false
            || choice.reasoningContent?.isEmpty == false
        {
            // A reasoning content already exists, so return the original choice.
            return choice
        }

        guard let content = choice.content else {
            return choice
        }

        let reasoningContentRef: Reference<String> = .init()
        let remainingContentRef: Reference<String> = .init()
        let regex = Regex {
            ZeroOrMore(.whitespace)
            REASONING_START_TOKEN
            Capture(as: reasoningContentRef) {
                ZeroOrMore(.any)
            } transform: {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            REASONING_END_TOKEN
            Capture(as: remainingContentRef) {
                ZeroOrMore(.any)
            } transform: {
                String($0.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        guard let match = content.wholeMatch(of: regex) else {
            // No reasoning content found, return the original choice.
            return choice
        }

        let reasoningContent = match[reasoningContentRef]
        let remainingContent = match[remainingContentRef]

        var newChoice = choice
        newChoice.content = remainingContent
        newChoice.reasoningContent = reasoningContent
        return newChoice
    }
}

class ToolCallCollector {
    var functionName: String = ""
    var functionArguments: String = ""
    var currentId: Int?
    var pendingRequests: [ToolCallRequest] = []

    func submit(delta: ChatCompletionChunk.Choice.Delta.ToolCall) {
        guard let function = delta.function else { return }

        if currentId != delta.index { finalizeCurrentDeltaContent() }
        currentId = delta.index

        if let name = function.name, !name.isEmpty {
            functionName.append(name)
        }
        if let arguments = function.arguments {
            functionArguments.append(arguments)
        }
    }

    func finalizeCurrentDeltaContent() {
        guard !functionName.isEmpty || !functionArguments.isEmpty else {
            return
        }
        let call = ToolCallRequest(name: functionName, args: functionArguments)
        print(call)
        pendingRequests.append(call)
        functionName = ""
        functionArguments = ""
    }
}

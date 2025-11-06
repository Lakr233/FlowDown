//
//  OpenAIResponses.swift
//  ChatClientKit
//
//  Created by LiBr on 2025/10/22.
//  Copyright (c) 2025 LiBr. All rights reserved.
//

import Foundation

// MARK: - Request Body Structures

public struct ResponsesRequestBody: Codable {
    public let background: Bool?
    public let conversation: ConversationInput?
    public let include: [String]?
    public let input: InputContent?
    public let instructions: String?
    public let maxOutputTokens: Int?
    public let maxToolCalls: Int?
    public let metadata: [String: String]?
    public let model: String?
    public let parallelToolCalls: Bool?
    public let previousResponseId: String?
    public let prompt: PromptTemplate?
    public let promptCacheKey: String?
    public let reasoning: ReasoningConfig?
    public let safetyIdentifier: String?
    public let serviceTier: String?
    public let store: Bool?
    public let stream: Bool?
    public let streamOptions: ChatRequestBody.StreamOptions?
    public let temperature: Double?
    public let text: TextConfig?
    public let toolChoice: ToolChoiceInput?
    public let tools: [ToolInput]?
    public let topLogprobs: Int?
    public let topP: Double?
    public let truncation: String?
    public let user: String?

    private enum CodingKeys: String, CodingKey {
        case background
        case conversation
        case include
        case input
        case instructions
        case maxOutputTokens = "max_output_tokens"
        case maxToolCalls = "max_tool_calls"
        case metadata
        case model
        case parallelToolCalls = "parallel_tool_calls"
        case previousResponseId = "previous_response_id"
        case prompt
        case promptCacheKey = "prompt_cache_key"
        case reasoning
        case safetyIdentifier = "safety_identifier"
        case serviceTier = "service_tier"
        case store
        case stream
        case streamOptions = "stream_options"
        case temperature
        case text
        case toolChoice = "tool_choice"
        case tools
        case topLogprobs = "top_logprobs"
        case topP = "top_p"
        case truncation
        case user
    }

    public init(
        background: Bool? = nil,
        conversation: ConversationInput? = nil,
        include: [String]? = nil,
        input: InputContent? = nil,
        instructions: String? = nil,
        maxOutputTokens: Int? = nil,
        maxToolCalls: Int? = nil,
        metadata: [String: String]? = nil,
        model: String? = nil,
        parallelToolCalls: Bool? = nil,
        previousResponseId: String? = nil,
        prompt: PromptTemplate? = nil,
        promptCacheKey: String? = nil,
        reasoning: ReasoningConfig? = nil,
        safetyIdentifier: String? = nil,
        serviceTier: String? = nil,
        store: Bool? = nil,
        stream: Bool? = nil,
        streamOptions: ChatRequestBody.StreamOptions? = nil,
        temperature: Double? = nil,
        text: TextConfig? = nil,
        toolChoice: ToolChoiceInput? = nil,
        tools: [ToolInput]? = nil,
        topLogprobs: Int? = nil,
        topP: Double? = nil,
        truncation: String? = nil,
        user: String? = nil
    ) {
        self.background = background
        self.conversation = conversation
        self.include = include
        self.input = input
        self.instructions = instructions
        self.maxOutputTokens = maxOutputTokens
        self.maxToolCalls = maxToolCalls
        self.metadata = metadata
        self.model = model
        self.parallelToolCalls = parallelToolCalls
        self.previousResponseId = previousResponseId
        self.prompt = prompt
        self.promptCacheKey = promptCacheKey
        self.reasoning = reasoning
        self.safetyIdentifier = safetyIdentifier
        self.serviceTier = serviceTier
        self.store = store
        self.stream = stream
        self.streamOptions = streamOptions
        self.temperature = temperature
        self.text = text
        self.toolChoice = toolChoice
        self.tools = tools
        self.topLogprobs = topLogprobs
        self.topP = topP
        self.truncation = truncation
        self.user = user
    }
}

// MARK: - Supporting Types

public enum ConversationInput: Codable {
    case string(String)
    case object([String: Any])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let dict = try? container.decode([String: JSONValue].self) {
            self = .object(dict.mapValues { $0.value })
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid conversation input"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(string):
            try container.encode(string)
        case let .object(dict):
            let jsonDict = dict.mapValues { JSONValue($0) }
            try container.encode(jsonDict)
        }
    }
}

public enum InputContent: Codable {
    case text(String)
    case items([InputItem])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let items = try? container.decode([InputItem].self) {
            self = .items(items)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid input content"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(string):
            try container.encode(string)
        case let .items(items):
            try container.encode(items)
        }
    }
}

public struct InputItem: Codable {
    public let type: String
    /// For message items, role must be one of: "assistant", "system", "developer", "user".
    /// Some servers (e.g. Codex/Responses) expect this at the top-level, not nested in content.
    public let role: String?
    /// Payload for the item. To support the desired wire format,
    /// this may be a plain string (e.g. message text) or an object.
    public let content: JSONValue?

    public init(type: String, role: String? = nil, content: Any? = nil) {
        self.type = type
        self.role = role
        if let content {
            self.content = JSONValue(content)
        } else {
            self.content = nil
        }
    }
}

public struct PromptTemplate: Codable {
    public let name: String?
    public let version: String?
    public let variables: [String: JSONValue]?

    public init(name: String? = nil, version: String? = nil, variables: [String: Any]? = nil) {
        self.name = name
        self.version = version
        self.variables = variables?.mapValues { JSONValue($0) }
    }
}

public struct ReasoningConfig: Codable {
    public let maxReasoningTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case maxReasoningTokens = "max_reasoning_tokens"
    }

    public init(maxReasoningTokens: Int? = nil) {
        self.maxReasoningTokens = maxReasoningTokens
    }
}

public struct TextConfig: Codable {
    public let type: String?
    public let schema: [String: JSONValue]?

    public init(type: String? = nil, schema: [String: Any]? = nil) {
        self.type = type
        self.schema = schema?.mapValues { JSONValue($0) }
    }
}

public enum ToolChoiceInput: Codable {
    case string(String)
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let dict = try? container.decode([String: JSONValue].self) {
            self = .object(dict)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid tool choice"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(string):
            try container.encode(string)
        case let .object(dict):
            try container.encode(dict)
        }
    }
}

public struct ToolInput: Codable {
    public let type: String
    public let definition: [String: JSONValue]

    public init(type: String, definition: [String: Any]) {
        self.type = type
        self.definition = definition.mapValues { JSONValue($0) }
    }
}

// MARK: - Response Body Structures

public struct ResponsesResponseBody: Codable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let serviceTier: String?
    public let usage: ResponsesUsage?
    public let outputs: [ResponseOutput]

    private enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case serviceTier = "service_tier"
        case usage
        case outputs
    }
}

public struct ResponsesUsage: Codable {
    public let promptTokens: Int?
    public let completionTokens: Int?
    public let totalTokens: Int?
    public let reasoningTokens: Int?

    private enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case reasoningTokens = "reasoning_tokens"
    }
}

public struct ResponseOutput: Codable {
    public let type: String

    // Common fields for "message" style payloads
    public let content: [String: JSONValue]?

    // Fields observed in Responses streaming delta events
    public let delta: String?
    public let text: String?
    public let part: [String: JSONValue]?
    public let item: [String: JSONValue]?

    public let sequenceNumber: Int?
    public let itemId: String?
    public let outputIndex: Int?
    public let contentIndex: Int?

    public let logprobs: [JSONValue]?
    public let obfuscation: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case content
        case delta
        case text
        case part
        case item
        case sequenceNumber = "sequence_number"
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case logprobs
        case obfuscation
    }

    public init(
        type: String,
        content: [String: Any]? = nil,
        delta: String? = nil,
        text: String? = nil,
        part: [String: Any]? = nil,
        item: [String: Any]? = nil,
        sequenceNumber: Int? = nil,
        itemId: String? = nil,
        outputIndex: Int? = nil,
        contentIndex: Int? = nil,
        logprobs: [Any]? = nil,
        obfuscation: String? = nil
    ) {
        self.type = type
        self.content = content?.mapValues { JSONValue($0) }
        self.delta = delta
        self.text = text
        self.part = part?.mapValues { JSONValue($0) }
        self.item = item?.mapValues { JSONValue($0) }
        self.sequenceNumber = sequenceNumber
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.contentIndex = contentIndex
        self.logprobs = logprobs?.map { JSONValue($0) }
        self.obfuscation = obfuscation
    }
}

// MARK: - Streaming Chunk

public struct ResponsesStreamingChunk: Codable {
    public let id: String?
    public let object: String?
    public let created: Int?
    public let model: String?
    public let serviceTier: String?
    public let usage: ResponsesUsage?
    public let outputs: [ResponseOutput]?

    private enum CodingKeys: String, CodingKey {
        case id
        case object
        case created
        case model
        case serviceTier = "service_tier"
        case usage
        case outputs
    }
}

/// Format handler for OpenAI Responses API
public final class OpenAIResponsesFormat: BaseChatFormat {
    private enum FormatError: LocalizedError {
        case invalidRequestBody
        case invalidStreamingPayload
        case unsupportedChatRequestBody

        var errorDescription: String? {
            switch self {
            case .invalidRequestBody:
                "Failed to serialize responses request body."
            case .invalidStreamingPayload:
                "Failed to parse responses streaming payload."
            case .unsupportedChatRequestBody:
                "ChatRequestBody is not directly supported by Responses API. Use ResponsesRequestBody instead."
            }
        }
    }

    override public var apiPath: String { "/v1/responses" }
    override public var formatName: String { "openai_responses" }
    override public var supportsStreaming: Bool { true }

    override public func prepareRequest(from body: ChatRequestBody, model: String, additionalFields: [String: Any]) throws -> Data {
        // Convert ChatRequestBody to ResponsesRequestBody
        let responsesBody = convertChatRequestToResponses(body, model: model)

        let bodyData = try JSONEncoder().encode(responsesBody)
        guard var requestDict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw FormatError.invalidRequestBody
        }

        // Add additional fields
        for (key, value) in additionalFields {
            requestDict[key] = value
        }

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    public func prepareResponsesRequest(from body: ResponsesRequestBody, additionalFields: [String: Any] = [:]) throws -> Data {
        let bodyData = try JSONEncoder().encode(body)
        guard var requestDict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw FormatError.invalidRequestBody
        }

        // Add additional fields
        for (key, value) in additionalFields {
            requestDict[key] = value
        }

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    override public func parseResponse(from data: Data) throws -> ChatResponseBody {
        let responsesResponse = try JSONDecoder().decode(ResponsesResponseBody.self, from: data)
        return convertResponsesToChatResponse(responsesResponse)
    }

    public func parseResponsesResponse(from data: Data) throws -> ResponsesResponseBody {
        try JSONDecoder().decode(ResponsesResponseBody.self, from: data)
    }

    override public func parseStreamingChunk(from data: Data) throws -> ChatCompletionChunk? {
        guard !data.isEmpty else { return nil }

        do {
            // First, try to decode as a standard Responses chunk.
            // Only accept it if it carries meaningful content/metadata; otherwise it might actually be an event envelope.
            let responsesChunk = try JSONDecoder().decode(ResponsesStreamingChunk.self, from: data)
            if (responsesChunk.outputs?.isEmpty == false) || responsesChunk.usage != nil || responsesChunk.id != nil || responsesChunk.model != nil {
                return convertResponsesToChatChunk(responsesChunk)
            }

            // If it decoded but is effectively empty, attempt to parse as an event envelope.
            if let evt = try parseEventEnvelope(from: data) {
                return evt
            }

            // As a last resort, try normalizing SSE payloads and retry both paths.
            if let normalized = ((try? normalizeSSEPayloadIfNeeded(data)) ?? nil) {
                if let evt = try parseEventEnvelope(from: normalized) {
                    return evt
                }
                let altChunk = try JSONDecoder().decode(ResponsesStreamingChunk.self, from: normalized)
                return convertResponsesToChatChunk(altChunk)
            }

            return nil
        } catch {
            guard var payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !payload.isEmpty
            else {
                throw error
            }

            if payload.caseInsensitiveCompare("[DONE]") == .orderedSame {
                return nil
            }

            // Extract data lines from Server-Sent Events payloads
            let dataLineValues = payload
                .split(whereSeparator: \.isNewline)
                .compactMap { rawLine -> String? in
                    let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespaces)
                    guard trimmedLine.lowercased().hasPrefix("data:") else { return nil }
                    guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
                    let valueStart = trimmedLine.index(after: colonIndex)
                    return String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
                }

            if !dataLineValues.isEmpty {
                payload = dataLineValues.joined(separator: "\n")
            }

            if payload.caseInsensitiveCompare("[DONE]") == .orderedSame {
                return nil
            }

            guard let sanitizedData = payload.data(using: .utf8) else {
                throw FormatError.invalidStreamingPayload
            }

            do {
                let responsesChunk = try JSONDecoder().decode(ResponsesStreamingChunk.self, from: sanitizedData)
                if (responsesChunk.outputs?.isEmpty == false) || responsesChunk.usage != nil || responsesChunk.id != nil || responsesChunk.model != nil {
                    return convertResponsesToChatChunk(responsesChunk)
                }
            } catch {
                // Attempt to parse ChatGPT Codex-style SSE event envelopes
                if let eventObj = try? JSONSerialization.jsonObject(with: sanitizedData) as? [String: Any],
                   let type = eventObj["type"] as? String
                {
                    // Completed/terminal events yield no content
                    if type == "response.completed" {
                        return nil
                    }
                    if type == "response.failed" {
                        // Surface a readable error, if present
                        if let response = eventObj["response"] as? [String: Any],
                           let errorDict = response["error"] as? [String: Any],
                           let message = errorDict["message"] as? String
                        {
                            throw NSError(domain: "Server Error", code: 400, userInfo: [NSLocalizedDescriptionKey: message])
                        }
                        throw FormatError.invalidStreamingPayload
                    }

                    // Token deltas can arrive in multiple shapes
                    if type == "response.output_text.delta" || type == "response.text.delta" || type == "response.delta" || type == "response.message.delta" {
                        // Only honor true delta keys to avoid duplication with content_part events
                        let deltaText = (eventObj["delta"] as? String) ?? (eventObj["text_delta"] as? String)
                        if let deltaText, !deltaText.isEmpty {
                            let choice = ChatCompletionChunk.Choice(delta: .init(content: deltaText, role: "assistant"))
                            return ChatCompletionChunk(choices: [choice])
                        }
                    }

                    // content_part.added sometimes carries inline text blocks (ignore *.done to prevent duplicates)
                    if type == "response.content_part.added" {
                        if let part = eventObj["part"] as? [String: Any] {
                            if let partType = part["type"] as? String, partType == "output_text" || partType == "text" {
                                if let t = part["text"] as? String, !t.isEmpty {
                                    let choice = ChatCompletionChunk.Choice(delta: .init(content: t, role: "assistant"))
                                    return ChatCompletionChunk(choices: [choice])
                                }
                            }
                        }
                    }
                    // Done markers should not emit additional content
                    if type == "response.output_item.done" || type == "response.output_text.done" {
                        return nil
                    }
                }

                // If we reach here, we couldn't recognize any valid content
                throw FormatError.invalidStreamingPayload
            }
            // No meaningful Responses chunk and no recognizable event; treat as no content
            return nil
        }
    }

    /// Normalize an SSE payload to raw JSON bytes if it contains `data:` lines.
    private func normalizeSSEPayloadIfNeeded(_ data: Data) throws -> Data? {
        guard var payload = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !payload.isEmpty else {
            return nil
        }
        if payload.caseInsensitiveCompare("[DONE]") == .orderedSame { return nil }

        let dataLineValues = payload
            .split(whereSeparator: \.isNewline)
            .compactMap { rawLine -> String? in
                let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard trimmedLine.lowercased().hasPrefix("data:") else { return nil }
                guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
                let valueStart = trimmedLine.index(after: colonIndex)
                return String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
            }
        if !dataLineValues.isEmpty {
            payload = dataLineValues.joined(separator: "\n")
        }
        if payload.caseInsensitiveCompare("[DONE]") == .orderedSame { return nil }
        return payload.data(using: .utf8)
    }

    /// Parse a single event-style streaming envelope into a ChatCompletionChunk if recognized.
    private func parseEventEnvelope(from data: Data) throws -> ChatCompletionChunk? {
        guard let eventObj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = eventObj["type"] as? String
        else { return nil }

        if type == "response.completed" { return nil }
        if type == "response.failed" {
            if let response = eventObj["response"] as? [String: Any],
               let errorDict = response["error"] as? [String: Any],
               let message = errorDict["message"] as? String
            {
                throw NSError(domain: "Server Error", code: 400, userInfo: [NSLocalizedDescriptionKey: message])
            }
            return nil
        }

        // Strict delta handling: only use true delta keys
        if ["response.output_text.delta", "response.text.delta", "response.delta", "response.message.delta", "text.delta", "output_text.delta"].contains(type) {
            let deltaText = (eventObj["delta"] as? String) ?? (eventObj["text_delta"] as? String)
            if let deltaText, !deltaText.isEmpty {
                let idx = (eventObj["output_index"] as? Int) ?? 0
                let role = idx == 0 ? "assistant" : nil
                let choice = ChatCompletionChunk.Choice(delta: .init(content: deltaText, role: role), index: idx)
                return ChatCompletionChunk(choices: [choice])
            }
        }

        // content_part.added carries inline text; ignore *.done
        if ["response.content_part.added", "content_part.added"].contains(type) {
            if let part = eventObj["part"] as? [String: Any],
               let partType = part["type"] as? String,
               partType == "output_text" || partType == "text",
               let t = part["text"] as? String, !t.isEmpty
            {
                let idx = (eventObj["output_index"] as? Int) ?? 0
                let role = idx == 0 ? "assistant" : nil
                let choice = ChatCompletionChunk.Choice(delta: .init(content: t, role: role), index: idx)
                return ChatCompletionChunk(choices: [choice])
            }
        }

        // Done markers should not emit any content
        if ["response.output_item.done", "output_item.done", "response.output_text.done", "output_text.done"].contains(type) {
            return nil
        }

        return nil
    }

    public func parseResponsesStreamingChunk(from data: Data) throws -> ResponsesStreamingChunk? {
        guard !data.isEmpty else { return nil }

        do {
            return try JSONDecoder().decode(ResponsesStreamingChunk.self, from: data)
        } catch {
            guard var payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !payload.isEmpty
            else {
                throw error
            }

            if payload.caseInsensitiveCompare("[DONE]") == .orderedSame {
                return nil
            }

            // Extract data lines from Server-Sent Events payloads
            let dataLineValues = payload
                .split(whereSeparator: \.isNewline)
                .compactMap { rawLine -> String? in
                    let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespaces)
                    guard trimmedLine.lowercased().hasPrefix("data:") else { return nil }
                    guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
                    let valueStart = trimmedLine.index(after: colonIndex)
                    return String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
                }

            if !dataLineValues.isEmpty {
                payload = dataLineValues.joined(separator: "\n")
            }

            if payload.caseInsensitiveCompare("[DONE]") == .orderedSame {
                return nil
            }

            guard let sanitizedData = payload.data(using: .utf8) else {
                throw FormatError.invalidStreamingPayload
            }

            do {
                return try JSONDecoder().decode(ResponsesStreamingChunk.self, from: sanitizedData)
            } catch {
                throw FormatError.invalidStreamingPayload
            }
        }
    }

    // MARK: - Conversion Methods

    private func convertChatRequestToResponses(_ chatRequest: ChatRequestBody, model: String) -> ResponsesRequestBody {
        // Convert messages to input items
        let inputItems = chatRequest.messages.compactMap { message -> InputItem? in
            switch message.role {
            case "system":
                return nil // System messages become instructions
            case "user":
                if case let .user(content, _) = message,
                   case let .text(text) = content
                {
                    // Move role to top-level and set content as a plain string
                    // to match the target format
                    return InputItem(
                        type: "message",
                        role: message.role,
                        content: text
                    )
                }
                return nil
            case "assistant":
                if case let .assistant(content, _, _, _) = message,
                   let contentValue = content,
                   case let .text(text) = contentValue
                {
                    // Move role to top-level and set content as a plain string
                    return InputItem(
                        type: "message",
                        role: message.role,
                        content: text
                    )
                }
                return nil
            default:
                return nil
            }
        }

        // Extract system instructions
        let instructions = chatRequest.messages.first { $0.role == "system" }
            .flatMap { message in
                if case let .system(content, _) = message,
                   case let .text(text) = content
                {
                    return text
                }
                return nil
            }

        return ResponsesRequestBody(
            background: nil,
            conversation: nil,
            include: nil,
            input: .items(inputItems),
            instructions: instructions,
            maxOutputTokens: nil,
            maxToolCalls: nil,
            metadata: nil,
            model: model,
            parallelToolCalls: nil,
            previousResponseId: nil,
            prompt: nil,
            promptCacheKey: nil,
            reasoning: nil,
            safetyIdentifier: nil,
            serviceTier: nil,
            store: nil,
            stream: chatRequest.stream,
            streamOptions: chatRequest.streamOptions,
            temperature: chatRequest.temperature,
            text: nil,
            toolChoice: nil,
            tools: nil,
            topLogprobs: nil,
            topP: chatRequest.topP,
            truncation: nil,
            user: nil
        )
    }

    private func convertResponsesToChatResponse(_ responsesResponse: ResponsesResponseBody) -> ChatResponseBody {
        let choices = responsesResponse.outputs.enumerated().map { _, output in
            let message = ChoiceMessage(
                content: extractTextFromOutput(output),
                role: "assistant"
            )
            return ChatChoice(
                finishReason: "stop",
                message: message
            )
        }

        let usage = responsesResponse.usage.map { responsesUsage in
            ChatUsage(
                completionTokens: responsesUsage.completionTokens,
                promptTokens: responsesUsage.promptTokens,
                totalTokens: responsesUsage.totalTokens,
                completionTokensDetails: nil
            )
        }

        return ChatResponseBody(
            choices: choices,
            created: responsesResponse.created,
            model: responsesResponse.model,
            usage: usage
        )
    }

    private func convertResponsesToChatChunk(_ responsesChunk: ResponsesStreamingChunk) -> ChatCompletionChunk {
        let choices: [ChatCompletionChunk.Choice] = responsesChunk.outputs?.enumerated().compactMap { enumeratedIndex, output in
            // Extract content from various output shapes, including delta events
            guard let contentText = extractTextFromOutput(output), !contentText.isEmpty else {
                return nil
            }

            let role: String? = if let oi = output.outputIndex {
                oi == 0 ? "assistant" : nil
            } else {
                enumeratedIndex == 0 ? "assistant" : nil
            }

            let delta = ChatCompletionChunk.Choice.Delta(
                content: contentText,
                role: role
            )
            let index = output.outputIndex ?? enumeratedIndex
            return ChatCompletionChunk.Choice(
                delta: delta,
                index: index
            )
        } ?? []

        let usage = responsesChunk.usage.map { responsesUsage in
            ChatUsage(
                completionTokens: responsesUsage.completionTokens,
                promptTokens: responsesUsage.promptTokens,
                totalTokens: responsesUsage.totalTokens,
                completionTokensDetails: nil
            )
        }

        return ChatCompletionChunk(
            choices: choices,
            created: responsesChunk.created,
            id: responsesChunk.id,
            model: responsesChunk.model,
            serviceTier: responsesChunk.serviceTier,
            usage: usage
        )
    }

    private func extractTextFromOutput(_ output: ResponseOutput) -> String? {
        // 1) Direct message content { type: "message", content: { text: "..." } }
        if output.type == "message" {
            if let content = output.content?["text"]?.value as? String, !content.isEmpty {
                return content
            }
        }

        // 2) Delta-style outputs: { type: "response.output_text.delta", delta: "..." }
        let deltaTypes: Set<String> = [
            "output_text.delta",
            "response.output_text.delta",
            "text.delta",
            "response.text.delta",
            "response.delta",
            "response.message.delta",
        ]
        if deltaTypes.contains(output.type) {
            if let d = output.delta, !d.isEmpty { return d }
        }

        // 3) content_part events with inline text blocks: { type: "response.content_part.added", part: { type: "text", text: "..." } }
        let contentPartTypes: Set<String> = [
            "response.content_part.added",
            "content_part.added",
        ]
        if contentPartTypes.contains(output.type) {
            if let partType = output.part?["type"]?.value as? String,
               partType == "output_text" || partType == "text",
               let t = output.part?["text"]?.value as? String,
               !t.isEmpty
            {
                return t
            }
        }

        // 4) Done markers: do not emit content
        let doneTypes: Set<String> = [
            "response.output_item.done",
            "output_item.done",
            "response.output_text.done",
            "output_text.done",
        ]
        if doneTypes.contains(output.type) { return nil }

        return nil
    }
}

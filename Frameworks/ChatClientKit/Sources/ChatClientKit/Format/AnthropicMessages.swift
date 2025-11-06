//
//  AnthropicMessages.swift
//  ChatClientKit
//
//  Created by LiBr on 2025/10/22.
//  Copyright (c) 2025 LiBr. All rights reserved.
//

import Foundation

// MARK: - Request Body Structures

public struct AnthropicMessagesRequestBody: Codable {
    public let model: String
    public let maxTokens: Int
    public let messages: [AnthropicMessage]
    public let system: String?
    public let metadata: AnthropicMetadata?
    public let stopSequences: [String]?
    public let stream: Bool?
    public let temperature: Double?
    public let topK: Int?
    public let topP: Double?
    public let tools: [AnthropicTool]?
    public let toolChoice: AnthropicToolChoice?

    private enum CodingKeys: String, CodingKey {
        case model
        case maxTokens = "max_tokens"
        case messages
        case system
        case metadata
        case stopSequences = "stop_sequences"
        case stream
        case temperature
        case topK = "top_k"
        case topP = "top_p"
        case tools
        case toolChoice = "tool_choice"
    }

    public init(
        model: String,
        maxTokens: Int,
        messages: [AnthropicMessage],
        system: String? = nil,
        metadata: AnthropicMetadata? = nil,
        stopSequences: [String]? = nil,
        stream: Bool? = nil,
        temperature: Double? = nil,
        topK: Int? = nil,
        topP: Double? = nil,
        tools: [AnthropicTool]? = nil,
        toolChoice: AnthropicToolChoice? = nil
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.messages = messages
        self.system = system
        self.metadata = metadata
        self.stopSequences = stopSequences
        self.stream = stream
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.tools = tools
        self.toolChoice = toolChoice
    }
}

// MARK: - Message Structures

public struct AnthropicMessage: Codable {
    public let role: String
    public let content: AnthropicContent

    public init(role: String, content: AnthropicContent) {
        self.role = role
        self.content = content
    }
}

public enum AnthropicContent: Codable {
    case text(String)
    case blocks([AnthropicContentBlock])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .text(string)
        } else if let blocks = try? container.decode([AnthropicContentBlock].self) {
            self = .blocks(blocks)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid content"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .text(string):
            try container.encode(string)
        case let .blocks(blocks):
            try container.encode(blocks)
        }
    }
}

public struct AnthropicContentBlock: Codable {
    public let type: String
    public let text: String?
    public let source: AnthropicImageSource?
    public let toolUseId: String?
    public let name: String?
    public let input: [String: JSONValue]?
    public let content: String?
    public let isError: Bool?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case source
        case toolUseId = "tool_use_id"
        case name
        case input
        case content
        case isError = "is_error"
    }

    public init(
        type: String,
        text: String? = nil,
        source: AnthropicImageSource? = nil,
        toolUseId: String? = nil,
        name: String? = nil,
        input: [String: Any]? = nil,
        content: String? = nil,
        isError: Bool? = nil
    ) {
        self.type = type
        self.text = text
        self.source = source
        self.toolUseId = toolUseId
        self.name = name
        self.input = input?.mapValues { JSONValue($0) }
        self.content = content
        self.isError = isError
    }
}

public struct AnthropicImageSource: Codable {
    public let type: String
    public let mediaType: String
    public let data: String

    private enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
    }

    public init(type: String, mediaType: String, data: String) {
        self.type = type
        self.mediaType = mediaType
        self.data = data
    }
}

// MARK: - Supporting Types

public struct AnthropicMetadata: Codable {
    public let userId: String?

    private enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }

    public init(userId: String? = nil) {
        self.userId = userId
    }
}

public struct AnthropicTool: Codable {
    public let name: String
    public let description: String?
    public let inputSchema: [String: JSONValue]

    private enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String? = nil, inputSchema: [String: Any]) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema.mapValues { JSONValue($0) }
    }
}

public enum AnthropicToolChoice: Codable {
    case auto
    case any
    case tool(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            switch string {
            case "auto":
                self = .auto
            case "any":
                self = .any
            default:
                self = .tool(string)
            }
        } else if let dict = try? container.decode([String: String].self),
                  let type = dict["type"],
                  type == "tool",
                  let name = dict["name"]
        {
            self = .tool(name)
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Invalid tool choice"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .auto:
            try container.encode("auto")
        case .any:
            try container.encode("any")
        case let .tool(name):
            try container.encode(["type": "tool", "name": name])
        }
    }
}

// MARK: - Response Body Structures

public struct AnthropicMessagesResponseBody: Codable {
    public let id: String
    public let type: String
    public let role: String
    public let content: [AnthropicContentBlock]
    public let model: String
    public let stopReason: String?
    public let stopSequence: String?
    public let usage: AnthropicUsage

    private enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case content
        case model
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }
}

public struct AnthropicUsage: Codable {
    public let inputTokens: Int
    public let outputTokens: Int

    private enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
    }
}

// MARK: - Streaming Structures

public struct AnthropicStreamingEvent: Codable {
    public let type: String
    public let message: AnthropicMessagesResponseBody?
    public let index: Int?
    public let contentBlock: AnthropicContentBlock?
    public let delta: AnthropicDelta?
    public let usage: AnthropicUsage?

    private enum CodingKeys: String, CodingKey {
        case type
        case message
        case index
        case contentBlock = "content_block"
        case delta
        case usage
    }
}

public struct AnthropicDelta: Codable {
    public let type: String?
    public let text: String?
    public let partialJson: String?
    public let stopReason: String?
    public let stopSequence: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case partialJson = "partial_json"
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }
}

/// Format handler for Anthropic Messages API
public final class AnthropicMessagesFormat: BaseChatFormat {
    private enum FormatError: LocalizedError {
        case invalidRequestBody
        case invalidStreamingPayload
        case unsupportedChatRequestBody

        var errorDescription: String? {
            switch self {
            case .invalidRequestBody:
                "Failed to serialize Anthropic messages request body."
            case .invalidStreamingPayload:
                "Failed to parse Anthropic streaming payload."
            case .unsupportedChatRequestBody:
                "ChatRequestBody conversion to Anthropic format failed."
            }
        }
    }

    override public var apiPath: String { "/v1/messages" }
    override public var formatName: String { "anthropic_messages" }
    override public var supportsStreaming: Bool { true }

    override public func prepareRequest(from body: ChatRequestBody, model: String, additionalFields: [String: Any]) throws -> Data {
        // Convert ChatRequestBody to AnthropicMessagesRequestBody
        let anthropicBody = convertChatRequestToAnthropic(body, model: model)

        let bodyData = try JSONEncoder().encode(anthropicBody)
        guard var requestDict = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else {
            throw FormatError.invalidRequestBody
        }

        // Add additional fields
        for (key, value) in additionalFields {
            requestDict[key] = value
        }

        return try JSONSerialization.data(withJSONObject: requestDict)
    }

    public func prepareAnthropicRequest(from body: AnthropicMessagesRequestBody, additionalFields: [String: Any] = [:]) throws -> Data {
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
        let anthropicResponse = try JSONDecoder().decode(AnthropicMessagesResponseBody.self, from: data)
        return convertAnthropicToChatResponse(anthropicResponse)
    }

    public func parseAnthropicResponse(from data: Data) throws -> AnthropicMessagesResponseBody {
        try JSONDecoder().decode(AnthropicMessagesResponseBody.self, from: data)
    }

    override public func parseStreamingChunk(from data: Data) throws -> ChatCompletionChunk? {
        guard !data.isEmpty else { return nil }

        do {
            let anthropicEvent = try parseAnthropicStreamingEvent(from: data)
            return convertAnthropicToChatChunk(anthropicEvent)
        } catch {
            // Handle [DONE] or invalid chunks
            guard var payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !payload.isEmpty
            else {
                throw error
            }

            if payload.caseInsensitiveCompare("[DONE]") == .orderedSame {
                return nil
            }

            // Extract event lines from Server-Sent Events payloads
            let eventLines = payload
                .split(whereSeparator: \.isNewline)
                .compactMap { rawLine -> String? in
                    let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespaces)
                    if trimmedLine.lowercased().hasPrefix("data:") {
                        guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
                        let valueStart = trimmedLine.index(after: colonIndex)
                        return String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
                    }
                    return nil
                }

            guard let eventData = eventLines.first,
                  !eventData.isEmpty,
                  let sanitizedData = eventData.data(using: .utf8)
            else {
                return nil
            }

            do {
                let anthropicEvent = try JSONDecoder().decode(AnthropicStreamingEvent.self, from: sanitizedData)
                return convertAnthropicToChatChunk(anthropicEvent)
            } catch {
                throw FormatError.invalidStreamingPayload
            }
        }
    }

    public func parseAnthropicStreamingEvent(from data: Data) throws -> AnthropicStreamingEvent? {
        guard !data.isEmpty else { return nil }

        do {
            return try JSONDecoder().decode(AnthropicStreamingEvent.self, from: data)
        } catch {
            guard var payload = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !payload.isEmpty
            else {
                throw error
            }

            // Extract event lines from Server-Sent Events payloads
            let eventLines = payload
                .split(whereSeparator: \.isNewline)
                .compactMap { rawLine -> String? in
                    let trimmedLine = String(rawLine).trimmingCharacters(in: .whitespaces)
                    if trimmedLine.lowercased().hasPrefix("data:") {
                        guard let colonIndex = trimmedLine.firstIndex(of: ":") else { return nil }
                        let valueStart = trimmedLine.index(after: colonIndex)
                        return String(trimmedLine[valueStart...]).trimmingCharacters(in: .whitespaces)
                    }
                    return nil
                }

            guard let eventData = eventLines.first,
                  !eventData.isEmpty,
                  let sanitizedData = eventData.data(using: .utf8)
            else {
                return nil
            }

            do {
                return try JSONDecoder().decode(AnthropicStreamingEvent.self, from: sanitizedData)
            } catch {
                throw FormatError.invalidStreamingPayload
            }
        }
    }

    // MARK: - Conversion Methods

    private func convertChatRequestToAnthropic(_ chatRequest: ChatRequestBody, model: String) -> AnthropicMessagesRequestBody {
        // Convert messages to Anthropic format
        var anthropicMessages: [AnthropicMessage] = []
        var systemMessage: String?

        for message in chatRequest.messages {
            switch message.role {
            case "system":
                if case let .system(content, _) = message,
                   case let .text(text) = content
                {
                    systemMessage = text
                }
            case "user":
                if case let .user(content, _) = message,
                   case let .text(text) = content
                {
                    anthropicMessages.append(AnthropicMessage(
                        role: message.role,
                        content: .text(text)
                    ))
                }
            case "assistant":
                if case let .assistant(content, _, _, _) = message,
                   let contentValue = content,
                   case let .text(text) = contentValue
                {
                    anthropicMessages.append(AnthropicMessage(
                        role: message.role,
                        content: .text(text)
                    ))
                }
            default:
                break
            }
        }

        return AnthropicMessagesRequestBody(
            model: model,
            maxTokens: 4096, // Default max tokens
            messages: anthropicMessages,
            system: systemMessage,
            stream: chatRequest.stream,
            temperature: chatRequest.temperature,
            topP: chatRequest.topP
        )
    }

    private func convertAnthropicToChatResponse(_ anthropicResponse: AnthropicMessagesResponseBody) -> ChatResponseBody {
        let content = anthropicResponse.content.compactMap { block in
            block.text
        }.joined(separator: "\n")

        let message = ChoiceMessage(
            content: content.isEmpty ? nil : content,
            role: anthropicResponse.role
        )

        let choice = ChatChoice(
            finishReason: anthropicResponse.stopReason,
            message: message
        )

        let usage = ChatUsage(
            completionTokens: anthropicResponse.usage.outputTokens,
            promptTokens: anthropicResponse.usage.inputTokens,
            totalTokens: anthropicResponse.usage.inputTokens + anthropicResponse.usage.outputTokens,
            completionTokensDetails: nil
        )

        return ChatResponseBody(
            choices: [choice],
            created: Int(Date().timeIntervalSince1970),
            model: anthropicResponse.model,
            usage: usage
        )
    }

    private func convertAnthropicToChatChunk(_ anthropicEvent: AnthropicStreamingEvent?) -> ChatCompletionChunk? {
        guard let event = anthropicEvent else { return nil }

        var delta = switch event.type {
        case "content_block_delta":
            ChatCompletionChunk.Choice.Delta(
                content: event.delta?.text,
                role: nil
            )
        case "message_start":
            ChatCompletionChunk.Choice.Delta(
                content: nil,
                role: event.message?.role
            )
        case "content_block_start":
            ChatCompletionChunk.Choice.Delta(
                content: event.contentBlock?.text,
                role: nil
            )
        default:
            ChatCompletionChunk.Choice.Delta()
        }

        let choice = ChatCompletionChunk.Choice(
            delta: delta,
            finishReason: event.delta?.stopReason,
            index: event.index ?? 0
        )

        let usage = event.usage.map { anthropicUsage in
            ChatUsage(
                completionTokens: anthropicUsage.outputTokens,
                promptTokens: anthropicUsage.inputTokens,
                totalTokens: anthropicUsage.inputTokens + anthropicUsage.outputTokens,
                completionTokensDetails: nil
            )
        }

        return ChatCompletionChunk(
            choices: [choice],
            created: Int(Date().timeIntervalSince1970),
            id: event.message?.id,
            model: event.message?.model,
            usage: usage
        )
    }
}

//
//  OpenAIChatCompletion.swift
//  ChatClientKit
//
//  Created by LiBr on 2025/10/22.
//  Copyright (c) 2025 LiBr. All rights reserved.
//

import Foundation

/// Format handler for OpenAI Chat Completions API
public final class OpenAIChatCompletionFormat: BaseChatFormat {
    private enum FormatError: LocalizedError {
        case invalidRequestBody
        case invalidStreamingPayload

        var errorDescription: String? {
            switch self {
            case .invalidRequestBody:
                "Failed to serialize chat request body."
            case .invalidStreamingPayload:
                "Failed to parse streaming payload."
            }
        }
    }

    override public var apiPath: String { "/v1/chat/completions" }
    override public var formatName: String { "openai_chat_completion" }
    override public var supportsStreaming: Bool { true }

    override public func prepareRequest(from body: ChatRequestBody, model: String, additionalFields: [String: Any]) throws -> Data {
        var modifiedBody = body
        modifiedBody.model = model

        // Encode ChatRequestBody to dictionary
        let bodyData = try JSONEncoder().encode(modifiedBody)
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
        try JSONDecoder().decode(ChatResponseBody.self, from: data)
    }

    override public func parseStreamingChunk(from data: Data) throws -> ChatCompletionChunk? {
        guard !data.isEmpty else { return nil }

        do {
            return try JSONDecoder().decode(ChatCompletionChunk.self, from: data)
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

            // Extract data lines from Server-Sent Events payloads (e.g. "data: {...}")
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
                return try JSONDecoder().decode(ChatCompletionChunk.self, from: sanitizedData)
            } catch {
                throw FormatError.invalidStreamingPayload
            }
        }
    }
}

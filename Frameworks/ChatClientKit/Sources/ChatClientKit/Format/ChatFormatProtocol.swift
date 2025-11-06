//
//  ChatFormatProtocol.swift
//  ChatClientKit
//
//  Created by LiBr on 2025/10/22.
//  Copyright (c) 2025 LiBr. All rights reserved.
//

import Foundation

/// Protocol define
public protocol ChatFormatProtocol: AnyObject {
    func prepareRequest(from body: ChatRequestBody, model: String, additionalFields: [String: Any]) throws -> Data

    func parseResponse(from data: Data) throws -> ChatResponseBody

    func parseStreamingChunk(from data: Data) throws -> ChatCompletionChunk?

    func parseError(from data: Data) -> Error?

    var apiPath: String { get }

    var formatName: String { get }

    var supportsStreaming: Bool { get }
}

/// Base implementation
open class BaseChatFormat: ChatFormatProtocol {
    public init() {}

    open var supportsStreaming: Bool { true }

    open func parseError(from data: Data) -> Error? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Standard { "error": { message, code } }
        if let errorDict = json["error"] as? [String: Any] {
            let message = errorDict["message"] as? String ?? String(localized: "Unknown Error", bundle: .module)
            let code = errorDict["code"] as? Int ?? 500
            return NSError(
                domain: String(localized: "Server Error"),
                code: code,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Server returns an error: \(code) \(message)", bundle: .module)]
            )
        }

        // Codex-style { "detail": "..." }
        if let detail = json["detail"] as? String {
            return NSError(
                domain: String(localized: "Server Error"),
                code: 400,
                userInfo: [NSLocalizedDescriptionKey: detail]
            )
        }

        return nil
    }

    open func prepareRequest(from _: ChatRequestBody, model _: String, additionalFields _: [String: Any]) throws -> Data {
        fatalError("prepareRequest must be implemented by subclass")
    }

    open func parseResponse(from _: Data) throws -> ChatResponseBody {
        fatalError("parseResponse must be implemented by subclass")
    }

    open func parseStreamingChunk(from _: Data) throws -> ChatCompletionChunk? {
        fatalError("parseStreamingChunk must be implemented by subclass")
    }

    open var apiPath: String {
        fatalError("apiPath must be implemented by subclass")
    }

    open var formatName: String {
        fatalError("formatName must be implemented by subclass")
    }
}

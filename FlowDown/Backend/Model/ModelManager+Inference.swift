//
//  ModelManager+Inference.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/29/25.
//

import ChatClientKit
import Foundation
import FoundationModels
import GPTEncoder
import MLX
import Storage
import UIKit

extension ModelManager {
    /// - imageProcessingFailure : "height: 1 must be larger than factor: 28"
    static let testImage: UIImage = .init(
        color: .accent,
        size: .init(width: 64, height: 64),
    )

    private static let testImageDataURL: URL? = {
        guard let data = testImage.pngData() else { return nil }
        let base64 = data.base64EncodedString()
        return URL(string: "data:image/png;base64,\(base64)")
    }()

    func testLocalModel(_ model: LocalModel, completion: @escaping (Result<Void, Error>) -> Void) {
        guard gpuSupportProvider() else {
            completion(.failure(NSError(domain: "GPU", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Your device does not support MLX."),
            ])))
            return
        }
        Task.detached {
            assert(!Thread.isMainThread)

            do {
                let client = try self.chatService(
                    for: model.id,
                    additionalBodyField: [:],
                )
                await client.errorCollector.clear()

                let userContent: ChatRequestBody.Message.MessageContent<String, [ChatRequestBody.Message.ContentPart]> = {
                    guard model.capabilities.contains(.visual),
                          let imageURL = Self.testImageDataURL
                    else {
                        return .text("YES or NO")
                    }
                    return .parts([
                        .text("YES or NO"),
                        .imageURL(imageURL, detail: .low),
                    ])
                }()

                let stream = try await client.streamingChat(
                    body: .init(
                        messages: [
                            .system(content: .text("Reply YES to every query.")),
                            .user(content: userContent),
                        ],
                        maxCompletionTokens: 32,
                        temperature: 0,
                    ),
                )

                var reasoningContent = ""
                var responseContent = ""
                var collectedToolCalls: [ToolRequest] = []

                for try await object in stream {
                    switch object {
                    case let .reasoning(value):
                        reasoningContent += value
                    case let .text(value):
                        responseContent += value
                    case let .tool(call):
                        collectedToolCalls.append(call)
                    case let .image(url):
                        // MARK: TODO

                        print(url)
                    }
                }

                var trimmedContent = responseContent
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                for terminator in ChatClientConstants.additionalTerminatingTokens {
                    while trimmedContent.hasSuffix(terminator) {
                        trimmedContent.removeLast(terminator.count)
                    }
                }

                trimmedContent = trimmedContent.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmedContent.isEmpty,
                   reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   collectedToolCalls.isEmpty
                {
                    if let error = client.collectedErrors, !error.isEmpty {
                        throw NSError(
                            domain: "Model",
                            code: -1,
                            userInfo: [NSLocalizedDescriptionKey: error],
                        )
                    }

                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to generate text.")],
                            ),
                        ),
                    )
                } else {
                    Logger.model.debugFile("model \(model.model_identifier) generates output for test case: \(trimmedContent)")
                    completion(.success(()))
                }
            } catch {
                Logger.model.errorFile("local model test failed: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
    }

    func testCloudModel(_ model: CloudModel, completion: @escaping (Result<Void, Error>) -> Void) {
        Task.detached { [weak self] in
            guard let self else { return }
            do {
                let inference = try await infer(
                    with: model.id,
                    maxCompletionTokens: 512,
                    input: [
                        .system(content: .text("Reply YES to every query.")),
                        .user(content: .text("YES or NO")),
                    ],
                )
                if !isEmptyResponse(inference) {
                    completion(.success(()))
                } else {
                    completion(
                        .failure(
                            NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: String(localized: "Model did not produce any textual output.")],
                            ),
                        ),
                    )
                }
            } catch {
                completion(.failure(error))
            }
        }
    }

}

extension ModelManager {
    /// Get the body fields configured for a cloud model
    /// - Parameter identifier: The model identifier
    /// - Returns: A dictionary of body fields, or empty dictionary if not found or empty
    public func modelBodyFields(for identifier: ModelIdentifier) -> [String: Any] {
        guard let model = cloudModel(identifier: identifier),
              !model.bodyFields.isEmpty,
              let data = model.bodyFields.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return [:]
        }
        return jsonObject
    }

    private static func hasNonEmptyText(_ text: String) -> Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func isEmptyResponse(_ response: ChatResponse) -> Bool {
        !Self.hasNonEmptyText(response.text)
            && !Self.hasNonEmptyText(response.reasoning)
            && response.tools.isEmpty
            && response.images.isEmpty
    }

    private func chatService(
        for identifier: ModelIdentifier,
        additionalBodyField: [String: Any],
    ) throws -> any ChatService {
        if let chatServiceFactory {
            return try chatServiceFactory(identifier, additionalBodyField)
        }
        return try makeDefaultChatService(
            for: identifier,
            additionalBodyField: additionalBodyField,
        )
    }

    private func makeDefaultChatService(
        for identifier: ModelIdentifier,
        additionalBodyField: [String: Any],
    ) throws -> any ChatService {
        if #available(iOS 26.0, macCatalyst 26.0, *), identifier == AppleIntelligenceModel.shared.modelIdentifier {
            return AppleIntelligenceChatClient()
        }
        if let model = cloudModel(identifier: identifier) {
            let endpoint = resolveEndpointComponents(from: model.endpoint)
            // Use additionalBodyField directly without merging model's bodyFields
            // Callers should explicitly merge bodyFields if needed
            switch model.response_format {
            case .chatCompletions:
                return RemoteCompletionsChatClient(
                    model: model.model_identifier,
                    baseURL: endpoint.baseURL,
                    path: endpoint.path,
                    apiKey: model.token,
                    additionalHeaders: model.headers,
                    additionalBodyField: additionalBodyField,
                )
            case .responses:
                return RemoteResponsesChatClient(
                    model: model.model_identifier,
                    baseURL: endpoint.baseURL,
                    path: endpoint.path,
                    apiKey: model.token,
                    additionalHeaders: model.headers,
                    additionalBodyField: additionalBodyField,
                )
            }
        } else if let model = localModel(identifier: identifier) {
            let preferredKind: MLXModelKind = model.capabilities.contains(.visual) ? .vlm : .llm
            return MLXChatClient(
                url: modelContent(for: model),
                preferredKind: preferredKind,
            )
        } else {
            throw NSError(
                domain: "Model",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Model not found.")],
            )
        }
    }

    private func resolveEndpointComponents(from endpoint: String) -> (baseURL: String?, path: String?) {
        guard !endpoint.isEmpty,
              let components = URLComponents(string: endpoint),
              components.host != nil
        else {
            return (endpoint.isEmpty ? nil : endpoint, endpoint.isEmpty ? nil : "/")
        }

        var baseComponents = URLComponents()
        baseComponents.scheme = components.scheme
        baseComponents.user = components.user
        baseComponents.password = components.password
        baseComponents.host = components.host
        baseComponents.port = components.port
        let baseURL = baseComponents.string

        var pathComponents = URLComponents()
        let pathValue = components.path.isEmpty ? "/" : components.path
        pathComponents.path = pathValue
        pathComponents.queryItems = components.queryItems
        pathComponents.fragment = components.fragment
        let normalizedPath = pathComponents.string ?? pathValue

        return (baseURL, normalizedPath)
    }

    func prepareRequestBody(
        modelID: ModelIdentifier,
        messages: [ChatRequestBody.Message],
    ) throws -> [ChatRequestBody.Message] {
        var messages = messages
        if let model = cloudModel(identifier: modelID) {
            // this model requires developer mode to work
            if model.capabilities.contains(.developerRole) {
                messages = messages.map { message in
                    switch message {
                    case let .system(content, name):
                        .developer(content: content, name: name)
                    default:
                        message
                    }
                }
            }
        }
        return messages
    }

    func infer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil,
        toolChoice: ChatRequestBody.ToolChoice? = nil,
    ) async throws -> ChatResponse {
        let (client, body) = try makeRequest(
            modelID: modelID,
            maxCompletionTokens: maxCompletionTokens,
            input: input,
            tools: tools,
            toolChoice: toolChoice,
        )
        return try await client.chat(body: body)
    }

    /// Builds the client and the request body shared by the buffered and the
    /// streaming entry points.
    private func makeRequest(
        modelID: ModelIdentifier,
        maxCompletionTokens: Int?,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]?,
        toolChoice: ChatRequestBody.ToolChoice?,
    ) throws -> (any ChatService, ChatRequestBody) {
        let client = try chatService(
            for: modelID,
            additionalBodyField: modelBodyFields(for: modelID),
        )
        var body = try ChatRequestBody(
            messages: prepareRequestBody(modelID: modelID, messages: input),
            maxCompletionTokens: maxCompletionTokens,
            temperature: temperature < 0 ? nil : .init(temperature),
            tools: tools,
            toolChoice: toolChoice,
        )
        body.preservesReasoningContent = modelCapabilities(identifier: modelID).contains(.preservedThinking)
        return (client, body)
    }

    func streamingInfer(
        with modelID: ModelIdentifier,
        maxCompletionTokens: Int? = nil,
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool]? = nil,
        toolChoice: ChatRequestBody.ToolChoice? = nil,
    ) async throws -> AsyncThrowingStream<ChatResponseChunk, Error> {
        let (client, body) = try makeRequest(
            modelID: modelID,
            maxCompletionTokens: maxCompletionTokens,
            input: input,
            tools: tools,
            toolChoice: toolChoice,
        )
        return AsyncThrowingStream(ChatResponseChunk.self, bufferingPolicy: .unbounded) { cont in
            Task.detached {
                let reasoningEmitter = BalancedEmitter(
                    duration: 1.0,
                    frequency: 30,
                ) { chunk in
                    cont.yield(.reasoning(chunk))
                }
                let textEmitter = BalancedEmitter(
                    duration: 0.5,
                    frequency: 20,
                ) { chunk in
                    cont.yield(.text(chunk))
                }
                cont.onTermination = { _ in
                    Task.detached {
                        await reasoningEmitter.cancel()
                        await textEmitter.cancel()
                    }
                }

                // 这个逻辑是这样的 如果 UI 吃到了太多的数据 布局一次可能要 0.1 秒
                // 布局完毕以后不会卡 但是一直在布局就会很卡
                // 所以如果输出超过 n 字 就停止使用 emitter
                // 由于 layout 只发生在 markdown 渲染的位置 因此只管 text 就行了
                var emotionalDamage = 0

                do {
                    let sequence = try await client.streamingChat(body: body)

                    for try await chunk in sequence {
                        switch chunk {
                        case let .reasoning(string):
                            await textEmitter.wait()
                            await reasoningEmitter.add(string)
                        case let .text(string):
                            await reasoningEmitter.wait()
                            if emotionalDamage >= 5000 {
                                await textEmitter.update(duration: 1.0, frequency: 3)
                            } else if emotionalDamage >= 2000 {
                                await textEmitter.update(duration: 1.0, frequency: 9)
                            } else if emotionalDamage >= 1000 {
                                await textEmitter.update(duration: 0.5, frequency: 15)
                            }
                            await textEmitter.add(string)
                            emotionalDamage += string.count
                        default:
                            await reasoningEmitter.wait()
                            await textEmitter.wait()
                            cont.yield(chunk)
                        }
                    }
                    await reasoningEmitter.wait()
                    await textEmitter.wait()
                    if emotionalDamage == 0 {
                        Logger.model.debugFile("model \(modelID) generated no text output in streaming inference")
                        if let error = client.collectedErrors {
                            cont.finish(throwing: NSError(
                                domain: "Model",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey: error],
                            ))
                            return
                        }
                    }
                    cont.finish()
                    return
                } catch {
                    cont.finish(throwing: error)
                    return
                }
            }
        }
    }

    func calculateEstimateTokensUsingCommonEncoder(
        input: [ChatRequestBody.Message],
        tools: [ChatRequestBody.Tool],
        includingReasoning: Bool = true,
    ) -> Int {
        assert(!Thread.isMainThread)

        func text(
            _ content: ChatRequestBody.Message.MessageContent<String, [String]>,
        ) -> String {
            switch content {
            case let .text(text):
                text
            case let .parts(strings):
                strings.joined(separator: "\n")
            }
        }

        // will pass to encoder later
        var estimatedInferenceText = ""

        // when processing images, assume 1 image = 512 tokens
        var estimatedAdditionalTokens = 0

        for message in input {
            switch message {
            case let .assistant(content, toolCalls, reasoning):
                estimatedInferenceText += "role: assistant\n"
                if let content { estimatedInferenceText += text(content) }
                // Reasoning only reaches the wire for preserved-thinking
                // models; counting it otherwise inflates the estimate and
                // triggers evictions the provider would never ask for.
                if includingReasoning, let reasoning, !reasoning.isEmpty {
                    estimatedInferenceText += "reasoning: \(reasoning)\n"
                }
                if let toolCalls, !toolCalls.isEmpty {
                    estimatedInferenceText += "calls: \(toolCalls)\n"
                }
            case let .system(content, name):
                estimatedInferenceText += "role: assistant\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .user(content, name):
                estimatedInferenceText += "role: user\n"
                if let name { estimatedInferenceText += "name: \(name)\n" }
                switch content {
                case let .text(text):
                    estimatedInferenceText += text
                case let .parts(contentParts):
                    for part in contentParts {
                        switch part {
                        case let .text(text): estimatedInferenceText += text
                        case .imageURL: estimatedAdditionalTokens += 512
                        case .audioBase64: estimatedAdditionalTokens += 1024
                        }
                    }
                }
            case let .developer(content, name):
                estimatedInferenceText += "role: developer\n"
                estimatedInferenceText += text(content)
                if let name { estimatedInferenceText += "name: \(name)\n" }
            case let .tool(content, id):
                estimatedInferenceText += "role: tool \(id)\n"
                estimatedInferenceText += text(content)
            }
        }

        if !tools.isEmpty {
            let encoder = JSONEncoder()
            if let toolText = try? encoder.encode(tools),
               let toolString = String(data: toolText, encoding: .utf8)
            {
                estimatedInferenceText += "tools: \(toolString)\n"
            } else { assertionFailure() }
        }

        let encoder = GPTEncoder()
        let tokens = encoder.encode(text: estimatedInferenceText)

        return tokens.count + estimatedAdditionalTokens
    }
}

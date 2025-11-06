//
//  Created by ktiays on 2025/2/18.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import CoreImage
import Foundation
import MLX
import MLXLLM
@preconcurrency import MLXLMCommon
import MLXVLM
import Tokenizers
import UIKit

// allow max 1 concurrent request
public class MLXChatClientQueue {
    let sem = DispatchSemaphore(value: 1)
    let lock = NSLock()
    var runningItems: Set<UUID> = []
    public func acquire() -> UUID {
        let token = UUID()
        lock.lock()
        runningItems.insert(token)
        lock.unlock()

        print("[+]", #function, token)
        sem.wait()
        return token
    }

    public func release(token: UUID) {
        lock.lock()
        defer { lock.unlock() }
        guard runningItems.contains(token) else {
            return
        }
        runningItems.remove(token)
        print("[+]", #function, token)
        sem.signal()
    }

    public static let shared = MLXChatClientQueue()
}

open class MLXChatClient: ChatService {
    private let url: URL
    private let modelConfiguration: ModelConfiguration
    private let emptyImage: CIImage = .init(cgImage: UIImage(
        color: .white,
        size: .init(width: 64, height: 64)
    ).cgImage!)

    // Hex UTF-8 bytes EF BF BD
    private static let decoderErrorSuffix = String(data: Data([0xEF, 0xBF, 0xBD]), encoding: .utf8)!

    public var collectedErrors: String?

    public init(url: URL) {
        self.url = url
        modelConfiguration = .init(directory: url)
    }

    public func chatCompletionRequest(body: ChatRequestBody) async throws -> ChatResponseBody {
        let choiceMessage: ChoiceMessage = try await streamingChatCompletionRequest(body: body)
            .compactMap { chunk -> ChatCompletionChunk? in
                switch chunk {
                case let .chatCompletionChunk(chunk): return chunk
                default: return nil // tool call
                }
            }
            .compactMap { $0.choices.first?.delta }
            .reduce(into: .init(content: "", reasoningContent: "", role: "")) { partialResult, delta in
                if let content = delta.content { partialResult.content?.append(content) }
                if let reasoningContent = delta.reasoningContent {
                    partialResult.reasoningContent?.append(reasoningContent)
                }
                for terminator in ChatClientConstants.additionalTerminatingTokens {
                    while partialResult.content?.hasSuffix(terminator) == true {
                        partialResult.content?.removeLast(terminator.count)
                    }
                }
            }
        let timestamp = Int(Date.now.timeIntervalSince1970)
        return .init(
            choices: [.init(message: choiceMessage)],
            created: timestamp,
            model: modelConfiguration.name
        )
    }

    public func streamingChatCompletionRequest(
        body: ChatRequestBody
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        let token = MLXChatClientQueue.shared.acquire()
        do {
            return try await streamingChatCompletionRequestExecute(body: body, token: token)
        } catch {
            MLXChatClientQueue.shared.release(token: token)
            throw error
        }
    }

    // MARK: - PRIVATE

    private func streamingChatCompletionRequestExecute(
        body: ChatRequestBody,
        token: UUID
    ) async throws -> AnyAsyncSequence<ChatServiceStreamObject> {
        var userInput = userInput(body: body)
        let generateParameters = generateParameters(body: body)
        let container: ModelContainer
        do {
            container = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration)
            // llm, remove image if found
            userInput.images = []
        } catch {
            do {
                container = try await VLMModelFactory.shared.loadContainer(configuration: modelConfiguration)
                // vlm, check for images
                if userInput.images.isEmpty { userInput.images.append(.ciImage(emptyImage)) }
            } catch {
                throw error
            }
        }

        let lockedInput = userInput
        return try await container.perform { context in
            let input = try await context.processor.prepare(input: lockedInput)

            return AsyncThrowingStream { continuation in
                var latestOutputLength = 0
                var isReasoning = false
                var shouldRemoveLeadingWhitespace = true

                func toggleReasoningIfNeeded(tokens: [Int]) -> Bool {
                    // check last token, because the reasoning token are special to become 1 token
                    if let lastToken = tokens.last {
                        let text = context.tokenizer.decode(tokens: [lastToken]).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !isReasoning, text == REASONING_START_TOKEN {
                            logger.info("starting reasoning with token \(text)")
                            isReasoning = true
                            return true
                        }
                        if isReasoning, text == REASONING_END_TOKEN {
                            logger.info("end reasoning with token \(text)")
                            isReasoning = false
                            return true
                        }
                    }
                    return false
                }

                func chunk(for text: String) -> ChatCompletionChunk? {
                    let chunkRange = latestOutputLength ..< text.count
                    let startIndex = text.index(text.startIndex, offsetBy: chunkRange.lowerBound)
                    let endIndex = text.index(text.startIndex, offsetBy: chunkRange.upperBound)
                    var chunkContent = String(text[startIndex ..< endIndex])

                    if shouldRemoveLeadingWhitespace {
                        chunkContent = chunkContent.trimmingCharactersFromStart(in: .whitespacesAndNewlines)
                        shouldRemoveLeadingWhitespace = chunkContent.isEmpty
                    }

                    guard !chunkContent.isEmpty else { return nil }

                    let delta = if isReasoning {
                        ChatCompletionChunk.Choice.Delta(reasoningContent: chunkContent)
                    } else {
                        ChatCompletionChunk.Choice.Delta(content: chunkContent)
                    }
                    let choice: ChatCompletionChunk.Choice = .init(delta: delta)
                    return .init(choices: [choice])
                }

                var regularContentOutputLength = 0

                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        let result = try MLXLMCommon.generate(
                            input: input,
                            parameters: generateParameters,
                            context: context
                        ) { tokens in
                            var text = context.tokenizer.decode(tokens: tokens)
                            defer { latestOutputLength = text.count }

                            while text.hasSuffix(Self.decoderErrorSuffix) {
                                text.removeLast(Self.decoderErrorSuffix.count)
                            }

                            if toggleReasoningIfNeeded(tokens: tokens) {
                                shouldRemoveLeadingWhitespace = true
                            } else {
                                if let chunk = chunk(for: text) {
                                    if !isReasoning {
                                        regularContentOutputLength += chunk.choices
                                            .compactMap(\.delta.content?.count)
                                            .reduce(0, +)
                                    }
                                    continuation.yield(ChatServiceStreamObject.chatCompletionChunk(chunk: chunk))
                                }
                            }

                            // for reasoning models, still expect something in return
                            // this is mainly because title generation requires that
                            if regularContentOutputLength >= body.maxCompletionTokens ?? 4096 {
                                return .stop
                            }

                            for terminator in ChatClientConstants.additionalTerminatingTokens {
                                var shouldTerminate = false
                                while text.hasSuffix(terminator) {
                                    text.removeLast(terminator.count)
                                    shouldTerminate = true
                                }
                                if shouldTerminate {
                                    print("[*] terminating due to additional terminator: \(terminator)")
                                    return .stop
                                }
                            }

                            if Task.isCancelled {
                                print("[-] cancelling current inference due to Task.isCancelled")
                                return .stop
                            }

                            return .more
                        }

                        let output = result.output
                        if let chunk = chunk(for: output) {
                            continuation.yield(ChatServiceStreamObject.chatCompletionChunk(chunk: chunk))
                        }

                        MLXChatClientQueue.shared.release(token: token)
                        continuation.finish()
                    } catch {
                        MLXChatClientQueue.shared.release(token: token)
                        continuation.finish(throwing: error)
                    }
                }
            }
        }.eraseToAnyAsyncSequence()
    }

    private func userInputContent(for messageContent: ChatRequestBody.Message.MessageContent<String, [String]>) -> String {
        switch messageContent {
        case let .text(text):
            text
        case let .parts(strings):
            strings.joined(separator: "\n")
        }
    }

    private func userInput(body: ChatRequestBody) -> UserInput {
        var messages: [[String: String]] = []
        var images: [UserInput.Image] = []
        for message in body.messages {
            switch message {
            case let .assistant(content, _, _, _):
                guard let content else {
                    continue
                }
                let msg = ["role": "assistant", "content": userInputContent(for: content)]
                messages.append(msg)
            case let .system(content, _):
                let msg = ["role": "system", "content": userInputContent(for: content)]
                messages.append(msg)
            case let .user(content, _):
                switch content {
                case let .text(text):
                    let msg = ["role": "user", "content": text]
                    messages.append(msg)
                case let .parts(contentParts):
                    for part in contentParts {
                        switch part {
                        case let .text(text):
                            let msg = ["role": "user", "content": text]
                            messages.append(msg)
                        case let .imageURL(url, _):
                            // The URL is a "local URL" containing base64 encoded image data.
                            // data:[<media-type>][;base64],<data>
                            guard let text = url.absoluteString.components(separatedBy: ";base64,").last,
                                  let data = Data(base64Encoded: text)
                            else {
                                assertionFailure()
                                continue
                            }
                            guard var image = UIImage(data: data) else {
                                assertionFailure()
                                continue
                            }
                            // now, if image is smaller then 64x64, we need to resize it
                            // hard limit on lower bound is 28x28 and variable to model
                            if image.size.width < 64 || image.size.height < 64 {
                                guard let resizedImage = image.resize(
                                    withSize: .init(width: 64, height: 64),
                                    contentMode: .contentAspectFit
                                ) else {
                                    assertionFailure()
                                    continue
                                }
                                image = resizedImage
                            }
                            // hard limit on upper bound is variable and variable to model but 512x512 should be ok
                            if image.size.width > 512 || image.size.height > 512 {
                                guard let resizedImage = image.resize(
                                    withSize: .init(width: 512, height: 512),
                                    contentMode: .contentAspectFit
                                ) else {
                                    assertionFailure()
                                    continue
                                }
                                image = resizedImage
                            }
                            guard let cgImage = image.cgImage else {
                                assertionFailure()
                                continue
                            }
                            let ciImage: CIImage = .init(cgImage: cgImage)
                            images.append(.ciImage(ciImage))
                        }
                    }
                }
            default:
                continue
            }
        }
        return .init(messages: messages, images: images)
    }

    private func generateParameters(body: ChatRequestBody) -> GenerateParameters {
        var parameters = GenerateParameters()
        if let temperature = body.temperature {
            parameters.temperature = Float(temperature)
        }
        if let topP = body.topP {
            parameters.topP = Float(topP)
        }
        if let penalty = body.frequencyPenalty {
            parameters.repetitionPenalty = Float(penalty)
        }
        return parameters
    }
}

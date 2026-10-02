//
//  TranslationProviderModel.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import ChatClientKit
import Combine
@preconcurrency import Storage
import SwiftUI

@MainActor
final class TranslationProviderModel: ObservableObject {
    private static let outputTranslationToolName = "output_translation"

    @Published private(set) var translationReasoning: String = ""
    @Published private(set) var translationPlainResult: String = ""
    @Published private(set) var translationSegmentedResult: [TranslationSegment] = []
    @Published private(set) var translationError: Error?
    @Published private(set) var isTranslating: Bool = false

    /// The translation to copy, falling back to the segments when the model replied only through the tool call.
    var copyableResult: String {
        if !translationPlainResult.isEmpty { return translationPlainResult }
        return translationSegmentedResult.map(\.translated).joined(separator: "\n")
    }

    private var translationTask: Task<Void, Never>?

    deinit {
        translationTask?.cancel()
    }

    func translate(
        inputText: String,
        model: CloudModel,
        language: String,
    ) {
        translationTask?.cancel()
        isTranslating = true
        translationError = nil

        translationTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await runTranslation(
                    inputText: inputText,
                    model: model,
                    language: language,
                )
            } catch {
                if !Task.isCancelled {
                    translationError = error
                }
            }

            // A cancelled task has already been replaced, so it must not touch the successor's handle.
            if !Task.isCancelled {
                isTranslating = false
                translationTask = nil
            }
        }
    }

    private func runTranslation(
        inputText: String,
        model: CloudModel,
        language: String,
    ) async throws {
        let endpoint = resolveEndpointComponents(from: model.endpoint)
        let body = try resolveBodyFields(model.bodyFields)
        let service = makeChatService(model: model, endpoint: endpoint, body: body)

        var messages: [ChatRequestBody.Message] = []

        // Keep every instruction in one leading message: the request skips the system-message
        // merging sanitizer, and some chat templates accept a system message only at the start.
        var instruction =
            """
            You are a professional translator. Your task is to translate the input text into \(language).

            Strict Rules:
            1. **Line-by-Line Correspondence**: The translated output must have exactly the same number of lines as the source text. Do not merge or split lines.
            2. **Pure Output**: Output ONLY the translated result. No explanations, no "Here is the translation", no quotes.
            3. **Plain Text**: Do NOT use Markdown, XML tags, or any special formatting.
            4. **Empty Lines**: If a specific line in the source is empty, keep it empty in the translation.

            The text to translate will be provided as the user message.
            """

        // Read on every request so an edit made in the app applies without relaunching the extension.
        // It goes before the tool instruction so the tool protocol stays the last instruction.
        let additional = additionalPrompt()
        if !additional.isEmpty {
            instruction += "\n\n" + additional
        }

        var tools: [ChatRequestBody.Tool] = []
        if model.capabilities.contains(.tool) {
            tools.append(outputTranslationTool)

            let toolInstruction =
                """
                IMPORTANT: Tools are available, do BOTH steps below.

                Step 1: Output the full translation as normal assistant text (streaming is allowed).
                - The output must preserve the exact number of lines from the input.
                - Output ONLY the translated result. No explanations, no quotes.

                Step 2: After finishing the translation text, call the tool `\(Self.outputTranslationToolName)` exactly once.
                - Provide the structured segments in `segments`.
                - Each segment must correspond to exactly one line in the input (including empty lines).
                - The number of segments MUST equal the number of input lines.
                - Do not add any extra assistant text after the tool call.
                """
            instruction += "\n\n" + toolInstruction
        }

        if model.capabilities.contains(.developerRole) {
            messages.append(.developer(content: .text(instruction)))
        } else {
            messages.append(.system(content: .text(instruction)))
        }

        messages.append(.user(content: .parts([.text(inputText)])))

        let request = ChatRequestBody(
            model: model.model_identifier,
            messages: messages,
            stream: true,
            tools: tools.isEmpty ? nil : tools,
        )

        translationReasoning = ""
        translationPlainResult = ""
        translationSegmentedResult = []

        struct OutputTranslationToolPayload: Decodable {
            struct Segment: Decodable {
                let input: String
                let translated: String
            }

            let segments: [Segment]
        }

        let stream = try await service.streamingChat(body: request)

        for try await chunk in stream {
            if Task.isCancelled { return }

            switch chunk {
            case let .reasoning(value):
                translationReasoning += value
            case let .text(value):
                translationPlainResult += value
            case let .tool(call):
                guard call.name.lowercased() == Self.outputTranslationToolName,
                      let payload = try? JSONDecoder().decode(
                          OutputTranslationToolPayload.self,
                          from: Data(call.args.utf8),
                      )
                else { break }
                translationSegmentedResult = payload.segments.map {
                    TranslationSegment(
                        input: $0.input,
                        translated: $0.translated,
                    )
                }
            default:
                break
            }
        }
        if Task.isCancelled { return }

        var normalizedPlain = translationPlainResult.trimmingCharacters(in: .whitespacesAndNewlines)
        for terminator in ChatClientConstants.additionalTerminatingTokens {
            while normalizedPlain.hasSuffix(terminator) {
                normalizedPlain.removeLast(terminator.count)
            }
        }
        normalizedPlain = normalizedPlain.trimmingCharacters(in: .whitespacesAndNewlines)
        translationPlainResult = normalizedPlain

        if normalizedPlain.isEmpty,
           translationReasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           translationSegmentedResult.isEmpty
        {
            let collected = service.collectedErrors?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let message = collected.isEmpty ? String(localized: "Failed to generate text.") : collected
            throw NSError(
                domain: "Translation",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: message],
            )
        }
    }

    private func makeChatService(
        model: CloudModel,
        endpoint: (baseURL: String?, path: String?),
        body: [String: Any],
    ) -> any ChatService {
        var dependencies = RemoteClientDependencies.live
        dependencies.requestSanitizer = EmptyRequestSanitizer()

        return switch model.response_format {
        case .chatCompletions:
            RemoteCompletionsChatClient(
                model: model.model_identifier,
                baseURL: endpoint.baseURL,
                path: endpoint.path,
                apiKey: model.token,
                additionalHeaders: model.headers,
                additionalBodyField: body,
                dependencies: dependencies,
            )
        case .responses:
            RemoteResponsesChatClient(
                model: model.model_identifier,
                baseURL: endpoint.baseURL,
                path: endpoint.path,
                apiKey: model.token,
                additionalHeaders: model.headers,
                additionalBodyField: body,
                dependencies: dependencies,
            )
        }
    }

    /// The Additional Prompt the app shares through the app group, or an empty string when none is set.
    private func additionalPrompt() -> String {
        guard let url = AppGroup.sharedAdditionalPromptURL,
              let data = try? Data(contentsOf: url)
        else { return "" }
        return String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var outputTranslationTool: ChatRequestBody.Tool {
        .function(
            name: Self.outputTranslationToolName,
            description: """
            Outputs the translation as structured segments.

            Use this tool AFTER streaming the full translation as assistant text.
            The segments must be line-by-line and preserve the exact number of lines from the source.

            You must use this tool.
            """,
            parameters: [
                "type": "object",
                "additionalProperties": false,
                "properties": [
                    "segments": [
                        "type": "array",
                        "description": "Structured segments (line-by-line). Must preserve the exact number of lines from the source.",
                        "items": [
                            "type": "object",
                            "additionalProperties": false,
                            "properties": [
                                "input": [
                                    "type": "string",
                                    "description": "The source segment text.",
                                ],
                                "translated": [
                                    "type": "string",
                                    "description": "The translated segment text.",
                                ],
                            ],
                            "required": ["input", "translated"],
                        ],
                    ],
                ],
                "required": ["segments"],
            ],
            strict: true,
        )
    }

    private func resolveBodyFields(_ input: String) throws -> [String: Any] {
        if input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        let object = try JSONSerialization.jsonObject(with: Data(input.utf8))
        guard let dictionary = object as? [String: Any] else {
            throw URLError(.unknown)
        }
        return dictionary
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
}

//
//  ConversationSession+ExecuteOnce.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    private enum StreamedMessageField {
        case reasoning
        case response

        func value(in message: Message) -> String {
            switch self {
            case .reasoning: message.reasoningContent
            case .response: message.document
            }
        }

        func update(_ value: String, in message: Message) {
            switch self {
            case .reasoning: message.update(\.reasoningContent, to: value)
            case .response: message.update(\.document, to: value)
            }
        }
    }

    /// Appends a streamed chunk to one of the message's text fields and reports
    /// the growth so the token counter and the stall watchdog stay honest.
    private func append(
        _ value: String,
        of message: Message,
        to field: StreamedMessageField,
    ) async {
        let currentValue = field.value(in: message)
        let newValue = currentValue + value
        field.update(newValue, in: message)
        let delta = newValue.count - currentValue.count
        guard delta > 0 else { return }
        recordVisibleProgress()
        await MainActor.run {
            ConversationSessionManager.shared.countIncomingTokens(delta)
        }
    }

    /// Streams one assistant turn and runs the tools it calls. Returns true
    /// when it ran tools, so the caller sends their results in a follow-up.
    func doMainInferenceOnce(
        _ modelID: ModelManager.ModelIdentifier,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ toolSet: ModelToolSet,
        _ modelWillExecuteTools: Bool,
        _ isImmediateFollowUpAfterToolCall: Bool,
    ) async throws -> Bool {
        await requestUpdate()
        showActivity()

        let message = appendNewMessage(role: .assistant)
        encodeAdditionalInfoAndAttachToMessage(message, dic: [
            "model_id": modelID,
        ])

        let tools = toolSet.definitions
        let stream = try await ModelManager.shared.streamingInfer(
            with: modelID,
            input: requestMessages,
            tools: tools,
        )
        defer { self.stopThinking(for: message.objectId) }

        var pendingToolCalls: [ToolRequest] = []
        var generatedImages: [ImageContent] = []

        for try await resp in stream {
            switch resp {
            case let .reasoning(value):
                await append(value, of: message, to: .reasoning)
            case let .text(value):
                await append(value, of: message, to: .response)
            case let .tool(call):
                // Tool-call deltas render nothing; without the indicator the
                // stream looks stalled while the model emits arguments.
                showActivity()
                pendingToolCalls.append(call)
            case let .image(imageContent):
                // Skip invalid image payloads
                guard UIImage(data: imageContent.data) != nil else {
                    Logger.model.warning(
                        "skip invalid generated image payload (size: \(imageContent.data.count) bytes)"
                    )
                    break
                }
                recordVisibleProgress()
                generatedImages.append(imageContent)

                let sequence = generatedImages.count
                let name = sequence > 1
                    ? String(localized: "Generated Image #\(sequence)")
                    : String(localized: "Generated Image")
                let attachments: [RichEditorView.Object.Attachment] = [
                    .init(
                        type: .image,
                        name: name,
                        previewImage: imageContent.data,
                        imageRepresentation: imageContent.data,
                        textRepresentation: "",
                        storageSuffix: UUID().uuidString,
                    ),
                ]

                let attachmentHolder = appendNewMessage(role: .user)
                attachmentHolder.update(\.document, to: String(localized: "Received an image"))
                markAsAttachmentHolder(attachmentHolder)
                addAttachments(attachments, to: attachmentHolder)
                await requestUpdate()
            }

            if !message.document.isEmpty {
                stopThinking(for: message.objectId)
            } else if !message.reasoningContent.isEmpty {
                startThinking(for: message.objectId)
            }
            await requestUpdate()
        }
        stopThinking(for: message.objectId)
        await requestUpdate()

        if !message.document.isEmpty {
            logger.infoFile("\(message.document)")
            let document = fixWebReferenceIfPossible(
                in: message.document,
                with: linkedContents.mapValues(\.absoluteString)
            )
            message.update(\.document, to: document)
        }

        if message.document.isEmpty, !generatedImages.isEmpty {
            let summary = generatedImages.count > 1
                ? String(localized: "Received \(generatedImages.count) images.")
                : String(localized: "Received an image")
            message.update(\.document, to: summary)
        }

        let trimmedReasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDocument = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
        let producedNothing = trimmedReasoning.isEmpty
            && trimmedDocument.isEmpty
            && generatedImages.isEmpty
            && pendingToolCalls.isEmpty

        // A cancelled consumer ends the stream normally instead of throwing,
        // so an empty round under cancellation is the user's cancellation.
        if producedNothing, Task.isCancelled {
            throw InferenceUserCancellationError()
        }

        let shouldSilentlyDropEmptyAssistantMessage = isImmediateFollowUpAfterToolCall && producedNothing

        if shouldSilentlyDropEmptyAssistantMessage {
            discard(messageIdentifier: message.objectId)
            await requestUpdate()
            return false
        }

        if !trimmedReasoning.isEmpty, trimmedDocument.isEmpty {
            let document = String(localized: "Thinking finished without output any content.")
            message.update(\.document, to: document)
            if !pendingToolCalls.isEmpty {
                // The placeholder is not the assistant's own words: the list
                // hides it, and replays must not send it either.
                markDocumentAsPlaceholder(message)
            }
        }

        pendingToolCalls = pendingToolCalls.map {
            ToolCallArgumentRepair.normalize(request: $0, using: tools)
        }

        await requestUpdate()
        requestMessages.append(
            .assistant(
                content: trimmedDocument.isEmpty ? nil : .text(message.document),
                toolCalls: pendingToolCalls.map {
                    .init(id: $0.id, function: .init(name: $0.name, arguments: $0.args))
                },
                reasoning: trimmedReasoning.isEmpty ? nil : trimmedReasoning,
            ),
        )

        if producedNothing {
            throw NSError(
                domain: "Inference Service",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "No response from model."),
                ],
            )
        }

        guard modelWillExecuteTools else {
            assert(pendingToolCalls.isEmpty)
            return false
        }
        guard !pendingToolCalls.isEmpty else { return false }

        try await performToolCalls(
            pendingToolCalls,
            toolSet: toolSet,
            modelID: modelID,
            requestMessages: &requestMessages,
        )
        return true
    }
}

//
//  ConversationSession+ExecuteOnce.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import ScrubberKit
import Storage
import UniformTypeIdentifiers

extension ConversationSession {
    /// Appends a streamed chunk to one of the message's text fields and reports
    /// the growth so the token counter and the stall watchdog stay honest.
    private func append(
        _ value: String,
        of message: Message,
        to keyPath: ReferenceWritableKeyPath<Message, String>,
    ) async {
        let oldCount = message[keyPath: keyPath].count
        let newValue = message[keyPath: keyPath] + value
        message.update(keyPath, to: newValue)
        let delta = newValue.count - oldCount
        guard delta > 0 else { return }
        recordVisibleProgress()
        await MainActor.run {
            ConversationSessionManager.shared.countIncomingTokens(delta)
        }
    }

    func doMainInferenceOnce(
        _ currentMessageListView: MessageListView,
        _ modelID: ModelManager.ModelIdentifier,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ tools: [ChatRequestBody.Tool]?,
        _ modelWillExecuteTools: Bool,
    ) async throws -> Bool {
        await requestUpdate()
        showActivity()

        let message = appendNewMessage(role: .assistant)
        encodeAdditionalInfoAndAttachToMessage(message, dic: [
            "model_id": modelID,
        ])

        let stream = try await ModelManager.shared.streamingInfer(
            with: modelID,
            input: requestMessages,
            tools: tools,
        )
        defer { self.stopThinking(for: message.objectId) }

        let isImmediateFollowUpAfterToolCall: Bool = if case .tool = requestMessages.last { true } else { false }
        var pendingToolCalls: [ToolRequest] = []
        var generatedImages: [ImageContent] = []
        let collapseAfterReasoningComplete = ModelManager.shared.collapseReasoningSectionWhenComplete
        var didCollapseReasoning = false

        for try await resp in stream {
            switch resp {
            case let .reasoning(value):
                await append(value, of: message, to: \.reasoningContent)
            case let .text(value):
                await append(value, of: message, to: \.document)
            case let .tool(call):
                // Tool-call deltas render nothing; without the indicator the
                // stream looks stalled while the model emits arguments.
                showActivity()
                pendingToolCalls.append(call)
            case let .image(imageContent):
                // Skip invalid image payloads
                guard UIImage(data: imageContent.data) != nil else {
                    Logger.model.warning("skip invalid generated image payload (size: \(imageContent.data.count) bytes)")
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
                addAttachments(attachments, to: attachmentHolder)
                await requestUpdate()
            }

            if !message.document.isEmpty {
                stopThinking(for: message.objectId)
                if collapseAfterReasoningComplete, !didCollapseReasoning {
                    didCollapseReasoning = true
                    message.update(\.isThinkingFold, to: true)
                }
            } else if !message.reasoningContent.isEmpty {
                startThinking(for: message.objectId)
            }
            await requestUpdate()
        }
        stopThinking(for: message.objectId)
        await requestUpdate()

        if collapseAfterReasoningComplete {
            message.update(\.isThinkingFold, to: true)
            await requestUpdate()
        }

        if !message.document.isEmpty {
            logger.infoFile("\(message.document)")
            let document = fixWebReferenceIfPossible(in: message.document, with: linkedContents.mapValues(\.absoluteString))
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
        let shouldSilentlyDropEmptyAssistantMessage = isImmediateFollowUpAfterToolCall
            && trimmedReasoning.isEmpty
            && trimmedDocument.isEmpty
            && generatedImages.isEmpty
            && pendingToolCalls.isEmpty

        if shouldSilentlyDropEmptyAssistantMessage {
            discard(messageIdentifier: message.objectId)
            await requestUpdate()
            return false
        }

        if !trimmedReasoning.isEmpty, trimmedDocument.isEmpty {
            let document = String(localized: "Thinking finished without output any content.")
            message.update(\.document, to: document)
        }

        pendingToolCalls = pendingToolCalls.map {
            ToolCallArgumentRepair.normalize(request: $0, using: tools)
        }

        await requestUpdate()
        requestMessages.append(
            .assistant(
                content: message.document.isEmpty ? nil : .text(message.document),
                toolCalls: pendingToolCalls.map {
                    .init(id: $0.id, function: .init(name: $0.name, arguments: $0.args))
                },
                reasoning: trimmedReasoning.isEmpty ? nil : trimmedReasoning,
            ),
        )

        if trimmedDocument.isEmpty, trimmedReasoning.isEmpty, generatedImages.isEmpty, pendingToolCalls.isEmpty {
            throw NSError(
                domain: "Inference Service",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "No response from model."),
                ],
            )
        }

        // 请求结束 如果没有启用工具调用就结束
        guard modelWillExecuteTools else {
            assert(pendingToolCalls.isEmpty)
            return false
        }
        guard !pendingToolCalls.isEmpty else { return false }
        assert(modelWillExecuteTools)

        await requestUpdate()
        showActivity(String(localized: "Utilizing tool call"))

        for request in pendingToolCalls {
            try checkCancellation()
            guard let tool = await ModelToolsManager.shared.findTool(for: request) else {
                Logger.chatService.errorFile("unable to find tool for request: \(request)")
                await Logger.chatService.infoFile("available tools: \(ModelToolsManager.shared.getEnabledToolsIncludeMCP())")
                throw NSError(
                    domain: "Tool Error",
                    code: -1,
                    userInfo: [
                        NSLocalizedDescriptionKey: String(localized: "Unable to process tool request with name: \(request.name)"),
                    ],
                )
            }
            showActivity(String(localized: "Utilizing tool: \(tool.interfaceName)"))

            // 检查是否是网络搜索工具，如果是则直接执行
            if let tool = tool as? MTWebSearchTool {
                let webSearchMessage = appendNewMessage(role: .webSearch)
                encodeToolRequestAndAttachToToolMessage(request, message: webSearchMessage)
                // The web search row reports its own progress from here on.
                hideActivity()
                let searchResult: [Scrubber.Document]
                do {
                    searchResult = try await tool.execute(
                        with: request.args,
                        session: self,
                        webSearchMessage: webSearchMessage,
                        anchorTo: currentMessageListView,
                    )
                } catch is CancellationError {
                    throw InferenceUserCancellationError()
                }
                var webAttachments: [RichEditorView.Object.Attachment] = []
                for doc in searchResult {
                    let index = requestLinkContentIndex(doc.url)
                    webAttachments.append(.init(
                        type: .text,
                        name: doc.title,
                        previewImage: .init(),
                        imageRepresentation: .init(),
                        textRepresentation: formatAsWebArchive(
                            document: doc.textDocument,
                            title: doc.title,
                            atIndex: index,
                        ),
                        storageSuffix: UUID().uuidString,
                    ))
                }
                showActivity()

                if webAttachments.isEmpty {
                    requestMessages.append(.tool(
                        content: .text(String(localized: "Web search returned no results.")),
                        toolCallID: request.id,
                    ))
                } else {
                    requestMessages.append(.tool(
                        content: .text(webAttachments.map(\.textRepresentation).joined(separator: "\n")),
                        toolCallID: request.id,
                    ))
                }
            } else {
                var toolStatus = Message.ToolStatus(name: tool.interfaceName, state: 0, message: "")
                let toolMessage = appendNewMessage(role: .toolHint)
                toolMessage.update(\.toolStatus, to: toolStatus)
                encodeToolRequestAndAttachToToolMessage(request, message: toolMessage)
                await requestUpdate()
                // The running tool row (and a possible confirmation dialog)
                // is the visible progress now.
                hideActivity()

                // 标准工具
                do {
                    let result = try await ModelToolsManager.shared.perform(
                        withTool: tool,
                        parms: request.args,
                        anchorTo: currentMessageListView,
                    )
                    var toolResponseText = result.text

                    let rawAttachmentCount = (result.imageAttachments.count + result.audioAttachments.count)
                    if rawAttachmentCount > 0 {
                        // form a user message for holding attachments
                        let collectorMessage = appendNewMessage(role: .user)

                        var editorObjects: [RichEditorView.Object.Attachment] = []

                        let imageAttachments = result.imageAttachments.map { image in
                            RichEditorView.Object.Attachment(
                                type: .image,
                                name: String(localized: "Tool Provided Image"),
                                previewImage: image.data,
                                imageRepresentation: image.data,
                                textRepresentation: "",
                                storageSuffix: UUID().uuidString,
                            )
                        }
                        editorObjects.append(contentsOf: imageAttachments)

                        var audioAttachments: [RichEditorView.Object.Attachment] = []
                        for (index, audio) in result.audioAttachments.enumerated() {
                            showActivity(String(localized: "Transcoding audio attachment \(index + 1)"))
                            do {
                                let fileExtension = audio.mimeType.flatMap { mime in
                                    UTType(mimeType: mime)?.preferredFilenameExtension
                                }
                                let transcoded = try await AudioTranscoder.transcode(
                                    data: audio.data,
                                    fileExtension: fileExtension,
                                )
                                var suggestedName = audio.name.trimmingCharacters(in: .whitespacesAndNewlines)
                                if suggestedName.isEmpty {
                                    suggestedName = if result.audioAttachments.count > 1 {
                                        String(localized: "Tool Provided Audio #\(index + 1)")
                                    } else {
                                        String(localized: "Tool Provided Audio")
                                    }
                                }
                                let attachment = try await RichEditorView.Object.Attachment.makeAudioAttachment(
                                    transcoded: transcoded,
                                    storage: nil,
                                    suggestedName: suggestedName,
                                )
                                audioAttachments.append(attachment)
                            } catch {
                                Logger.model.errorFile("failed to process audio attachment from tool \(tool.interfaceName): \(error.localizedDescription)")
                            }
                        }
                        editorObjects.append(contentsOf: audioAttachments)
                        let finalAttachmentCount = editorObjects.count
                        collectorMessage.update(\.document, to: String(
                            localized: "Collected \(finalAttachmentCount) attachments from tool \(tool.interfaceName).",
                        ))

                        toolResponseText = collectorMessage.document

                        addAttachments(editorObjects, to: collectorMessage)
                        updateAttachments(editorObjects, for: collectorMessage)
                        await requestUpdate()

                        // 如果模型支持图片则添加到请求消息中 如果不支持 tool 一般已经返回了需要的 text 信息
                        let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelID)
                        let messages = await makeMessageFromAttachments(
                            editorObjects,
                            modelCapabilities: modelCapabilities,
                        )
                        requestMessages.append(contentsOf: messages)
                    }

                    // 64k len is quite large already
                    let toolResponseLimit = 64 * 1024
                    if toolResponseText.count > toolResponseLimit {
                        toolResponseText = """
                        \(String(toolResponseText.prefix(toolResponseLimit)))...
                        [truncated output due to length exceeding \(toolResponseLimit) characters]
                        """
                    }

                    toolStatus.state = 1
                    toolStatus.message = toolResponseText
                    toolMessage.update(\.toolStatus, to: toolStatus)
                    await requestUpdate()
                    let finalToolContent = toolResponseText.trimmingCharacters(in: .whitespacesAndNewlines)
                    requestMessages.append(.tool(
                        content: .text(finalToolContent.isEmpty ? String(localized: "Tool executed successfully with no output") : toolResponseText),
                        toolCallID: request.id,
                    ))
                } catch {
                    let cancelled = error is CancellationError || error is InferenceUserCancellationError
                    toolStatus.state = 2
                    toolStatus.message = cancelled
                        ? String(localized: "Cancelled by user.")
                        : error.localizedDescription
                    toolMessage.update(\.toolStatus, to: toolStatus)
                    save()
                    await requestUpdate()
                    // The row is settled; only then may cancellation abort the
                    // round, otherwise it would stay "running" forever.
                    if cancelled { throw InferenceUserCancellationError() }
                    requestMessages.append(.tool(content: .text("Tool execution failed. Reason: \(error.localizedDescription)"), toolCallID: request.id))
                }
            }
        }

        await requestUpdate()
        return true
    }
}

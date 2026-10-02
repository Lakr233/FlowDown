//
//  ConversationSession+BuildMessages.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    func buildInitialRequestMessages(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelCapabilities: Set<ModelCapabilities>,
    ) async {
        let stored = messages
        for (index, message) in stored.enumerated() {
            switch message.role {
            case .system:
                guard !message.document.isEmpty else { continue }
                requestMessages.append(.system(content: .text(message.document)))
            case .user:
                let attachments: [RichEditorView.Object.Attachment] = attachments(for: message.objectId).compactMap {
                    guard let type = RichEditorView.Object.Attachment.AttachmentType(rawValue: $0.type) else {
                        return nil
                    }
                    return .init(
                        type: type,
                        name: $0.name,
                        previewImage: $0.previewImageData,
                        imageRepresentation: $0.imageRepresentation,
                        textRepresentation: $0.representedDocument,
                        storageSuffix: $0.storageSuffix,
                    )
                }
                let attachmentMessages = await makeMessageFromAttachments(
                    attachments,
                    modelCapabilities: modelCapabilities,
                )
                if !attachmentMessages.isEmpty {
                    // Add the content of the previous attachments to the conversation context.
                    requestMessages.append(contentsOf: attachmentMessages)
                }
                if !message.document.isEmpty {
                    requestMessages.append(.user(content: .text(message.document)))
                } else {
                    assertionFailure()
                }
            case .assistant:
                guard !message.document.isEmpty else { continue }
                // Reasoning rides along for preserved-thinking models; the
                // encoder drops it unless the model opted in.
                let reasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
                if documentIsPlaceholder(message),
                   stored.indices.contains(index + 1),
                   replaysStoredToolCall(stored[index + 1])
                {
                    // The tool call replayed next carries this turn; send the
                    // reasoning without the UI placeholder text. Without that
                    // row (deleted, or cancelled before it was made) the text
                    // stays, so the turn never goes out empty.
                    guard !reasoning.isEmpty else { continue }
                    requestMessages.append(.assistant(content: nil, reasoning: reasoning))
                    continue
                }
                requestMessages.append(.assistant(
                    content: .text(message.document),
                    reasoning: reasoning.isEmpty ? nil : reasoning,
                ))
            case .webSearch:
                var index = 0
                let searchResults = message.webSearchStatus.searchResults.map {
                    index += 1
                    return """
                    <index>\(index)</index>
                    <title>\($0.title)</title>
                    <url>\($0.url.absoluteString)</url>
                    <content>\($0.toolResult)</content>
                    """
                }
                guard let replay = await replayStoredToolCall(
                    from: message,
                    output: searchResults.joined(separator: "\n"),
                    emptyOutput: String(localized: "Search completed with no results"),
                ) else { return }
                requestMessages.append(contentsOf: replay)
            case .toolHint:
                guard let replay = await replayStoredToolCall(
                    from: message,
                    output: message.toolStatus.message,
                    emptyOutput: String(localized: "Tool executed successfully with no output"),
                ) else { return }
                requestMessages.append(contentsOf: replay)
            default:
                continue
            }
        }
    }

    /*
     {
       "error": {
         "message": "Provider returned error",
         "metadata": {
           "raw": "{\n  \"error\": {\n    \"message\": \"Missing required parameter: 'input[6].arguments'.\",\n    \"type\": \"invalid_request_error\",\n    \"param\": \"input[6].arguments\",\n    \"code\": \"missing_required_parameter\"\n  }\n}",
           "provider_name": "Azure"
         },
         "code": 400
       },
     }
     */

    /// Replays a stored tool call as the provider expects to see it: the
    /// assistant turn that requested the call, followed by the tool turn that
    /// carries its output. Returns nil when the stored request cannot be
    /// decoded, which aborts the whole rebuild.
    private func replayStoredToolCall(
        from message: Message,
        output: String,
        emptyOutput: String,
    ) async -> [ChatRequestBody.Message]? {
        guard let toolRequest = decodeToolRequestFromToolMessage(message) else { return nil }
        let normalized = await normalizeStoredToolRequest(toolRequest)
        let isEmpty = output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return [
            .assistant(content: nil, toolCalls: [
                .init(
                    id: normalized.id,
                    function: .init(name: normalized.name, arguments: normalized.args),
                ),
            ]),
            .tool(content: .text(isEmpty ? emptyOutput : output), toolCallID: normalized.id),
        ]
    }

    func encodeAdditionalInfoAndAttachToMessage(_ message: Message, dic: [String: Any]) {
        var existing = metadataDictionary(of: message) ?? [:]
        for (key, value) in dic {
            existing[key] = value
        }
        let data = try? JSONSerialization.data(withJSONObject: existing, options: [.fragmentsAllowed])
        message.update(\.metadata, to: data)
        logger.debugFile("[*] encoded additional info to message \(message.objectId) with value \(dic)")
    }

    func encodeToolRequestAndAttachToToolMessage(_ toolRequest: ToolRequest, message: Message) {
        let precoded = try? JSONEncoder().encode(toolRequest)
        let predic = try? JSONSerialization.jsonObject(
            with: precoded ?? .init(),
            options: [.fragmentsAllowed]
        ) as? [String: Any]
        encodeAdditionalInfoAndAttachToMessage(message, dic: ["tool_request": predic ?? [:]])
        logger.debugFile(
            "[*] encoded tool request \(toolRequest.name) to message \(message.objectId) with value \(predic ?? [:])"
        )
    }

    /// Marks the message's document as a UI placeholder rather than model
    /// output. Storing the text itself lets a later edit clear the mark.
    func markDocumentAsPlaceholder(_ message: Message) {
        encodeAdditionalInfoAndAttachToMessage(message, dic: ["placeholder_document": message.document])
    }

    func documentIsPlaceholder(_ message: Message) -> Bool {
        guard let placeholder = metadataDictionary(of: message)?["placeholder_document"] as? String else {
            return false
        }
        return placeholder == message.document
    }

    /// Whether the row replays as an assistant tool-call turn, which then
    /// merges with the assistant turn right before it.
    private func replaysStoredToolCall(_ message: Message) -> Bool {
        switch message.role {
        case .toolHint, .webSearch:
            decodeToolRequestFromToolMessage(message) != nil
        default:
            false
        }
    }

    func decodeToolRequestFromToolMessage(_ message: Message) -> ToolRequest? {
        guard let toolRequestDic = metadataDictionary(of: message)?["tool_request"],
              let data = try? JSONSerialization.data(withJSONObject: toolRequestDic, options: [.fragmentsAllowed]),
              let toolRequest = try? JSONDecoder().decode(ToolRequest.self, from: data)
        else { return nil }
        return toolRequest
    }

    /// The message metadata as a JSON object, or nil when it is missing or not a dictionary.
    private func metadataDictionary(of message: Message) -> [String: Any]? {
        guard let metadata = message.metadata else { return nil }
        return try? JSONSerialization.jsonObject(with: metadata, options: [.fragmentsAllowed]) as? [String: Any]
    }

    func normalizeStoredToolRequest(_ request: ToolRequest) async -> ToolRequest {
        guard let tool = await ModelToolsManager.shared.findTool(for: request) else {
            return ToolCallArgumentRepair.normalize(request: request, using: nil)
        }
        return ToolCallArgumentRepair.normalize(
            request: request,
            using: [tool.definition]
        )
    }

    func makeMessageFromAttachments(
        _ attachments: [RichEditorView.Object.Attachment],
        modelCapabilities: Set<ModelCapabilities>,
    ) async -> [ChatRequestBody.Message] {
        let supportsVision = modelCapabilities.contains(.visual)
        let supportsAudio = modelCapabilities.contains(.auditory)
        var result: [ChatRequestBody.Message] = []
        for attach in attachments {
            if let message = await processAttachments(
                attach,
                supportsVision: supportsVision,
                supportsAudio: supportsAudio,
            ) {
                result.append(message)
            }
        }
        return result
    }

    private func processAttachments(
        _ attachment: RichEditorView.Object.Attachment,
        supportsVision: Bool,
        supportsAudio: Bool,
    ) async -> ChatRequestBody.Message? {
        switch attachment.type {
        case .text:
            return .user(
                content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n"))
            )
        case .image:
            if supportsVision {
                guard let image = UIImage(data: attachment.imageRepresentation),
                      let base64 = image.pngBase64String(),
                      let url = URL(string: "data:image/png;base64,\(base64)")
                else {
                    assertionFailure()
                    return nil
                }
                if !attachment.textRepresentation.isEmpty {
                    return .user(
                        content: .parts([
                            .imageURL(url),
                            .text(attachment.textRepresentation),
                        ]),
                    )
                } else {
                    return .user(content: .parts([.imageURL(url)]))
                }
            } else {
                guard !attachment.textRepresentation.isEmpty else {
                    logger.infoFile("[-] image attachment ignored because not processed")
                    return nil
                }
                return .user(
                    content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n"))
                )
            }
        case .audio:
            if supportsAudio {
                let data = attachment.imageRepresentation
                // treat this data as m4a, process to transcoding what's so ever
                do {
                    let content = try await AudioTranscoder.transcode(
                        data: data,
                        fileExtension: "m4a",
                        output: .compressedQualityWAV
                    )
                    let base64 = content.data.base64EncodedString()
                    var parts: [ChatRequestBody.Message.ContentPart] = [
                        .audioBase64(base64, format: "wav"),
                    ]
                    let description = attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !description.isEmpty {
                        parts.append(.text(["[\(attachment.name)]", description].joined(separator: "\n")))
                    } else {
                        parts.append(.text("[\(attachment.name)]"))
                    }
                    return .user(content: .parts(parts))
                } catch {
                    logger.errorFile("[-] audio attachment transcoding failed: \(error.localizedDescription)")
                    return .user(
                        content: .text(
                            "Audio attachment \"\(attachment.name)\" was skipped because transcoding failed."
                        )
                    )
                }
            } else {
                let description = attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
                if description.isEmpty {
                    let fallback = String(localized: "Audio attachment \"\(attachment.name)\" was skipped because the active model does not support audio input.")
                    return .user(content: .text(fallback))
                } else {
                    return .user(content: .text(["[\(attachment.name)]", description].joined(separator: "\n")))
                }
            }
        }
    }
}

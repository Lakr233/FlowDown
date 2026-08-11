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
        for message in messages {
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
                requestMessages.append(.assistant(
                    content: .text(message.document),
                    reasoning: reasoning.isEmpty ? nil : reasoning,
                ))
            case .webSearch:
                let result = message.webSearchStatus.searchResults
                var index = 0
                let content = result.compactMap {
                    index += 1
                    return """
                    <index>\(index)</index>
                    <title>\($0.title)</title>
                    <url>\($0.url.absoluteString)</url>
                    <content>\($0.toolResult)</content>
                    """
                }
                guard let toolRequest = decodeToolRequestFromToolMessage(message) else {
                    return
                }
                let normalizedToolRequest = await normalizeStoredToolRequest(toolRequest)
                requestMessages.append(.assistant(content: nil, toolCalls: [
                    .init(
                        id: normalizedToolRequest.id,
                        function: .init(
                            name: normalizedToolRequest.name,
                            arguments: normalizedToolRequest.args
                        )
                    ),
                ]))
                let webSearchContent = content.joined(separator: "\n")
                requestMessages.append(.tool(
                    content: .text(webSearchContent.isEmpty ? String(localized: "Search completed with no results") : webSearchContent),
                    toolCallID: normalizedToolRequest.id,
                ))
            case .toolHint:
                let content = message.toolStatus.message
                guard let toolRequest = decodeToolRequestFromToolMessage(message) else {
                    return
                }
                let normalizedToolRequest = await normalizeStoredToolRequest(toolRequest)
                requestMessages.append(.assistant(content: nil, toolCalls: [
                    .init(
                        id: normalizedToolRequest.id,
                        function: .init(
                            name: normalizedToolRequest.name,
                            arguments: normalizedToolRequest.args
                        )
                    ),
                ]))
                let toolContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
                requestMessages.append(.tool(
                    content: .text(toolContent.isEmpty ? String(localized: "Tool executed successfully with no output") : content),
                    toolCallID: normalizedToolRequest.id,
                ))
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

    func encodeAdditionalInfoAndAttachToMessage(_ message: Message, dic: [String: Any]) {
        let read = message.metadata ?? .init()
        let orig = try? JSONSerialization.jsonObject(with: read, options: [.fragmentsAllowed]) as? [String: Any]
        var existing = orig ?? .init()
        for (key, value) in dic {
            existing[key] = value
        }
        let data = try? JSONSerialization.data(withJSONObject: existing, options: [.fragmentsAllowed])
        message.update(\.metadata, to: data)
        logger.debugFile("[*] encoded additional info to message \(message.objectId) with value \(dic)")
    }

    func encodeToolRequestAndAttachToToolMessage(_ toolRequest: ToolRequest, message: Message) {
        let precoded = try? JSONEncoder().encode(toolRequest)
        let predic = try? JSONSerialization.jsonObject(with: precoded ?? .init(), options: [.fragmentsAllowed]) as? [String: Any]
        encodeAdditionalInfoAndAttachToMessage(message, dic: ["tool_request": predic ?? [:]])
        logger.debugFile("[*] encoded tool request \(toolRequest.name) to message \(message.objectId) with value \(predic ?? [:])")
    }

    func decodeToolRequestFromToolMessage(_ message: Message) -> ToolRequest? {
        let read = message.metadata ?? .init()
        guard let orig = try? JSONSerialization.jsonObject(with: read, options: [.fragmentsAllowed]) as? [String: Any],
              let toolRequestDic = orig["tool_request"],
              let data = try? JSONSerialization.data(withJSONObject: toolRequestDic, options: [.fragmentsAllowed]),
              let toolRequest = try? JSONDecoder().decode(ToolRequest.self, from: data)
        else { return nil }
        return toolRequest
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
            return .user(content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n")))
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
                return .user(content: .text(["[\(attachment.name)]", attachment.textRepresentation].joined(separator: "\n")))
            }
        case .audio:
            if supportsAudio {
                let data = attachment.imageRepresentation
                // treat this data as m4a, process to transcoding what's so ever
                do {
                    let content = try await AudioTranscoder.transcode(data: data, fileExtension: "m4a", output: .compressedQualityWAV)
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
                    return .user(content: .text("Audio attachment \"\(attachment.name)\" was skipped because transcoding failed."))
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

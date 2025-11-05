//
//  ConversationSession+BuildMessages.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import RichEditor
import Storage

extension ConversationSession {
    func buildInitialRequestMessages(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelCapabilities: Set<ModelCapabilities>,
        limitToMessageId: Message.ID?
    ) {
        for message in messages {
            if let limitToMessageId, message.objectId == limitToMessageId {
                break
            }
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
                        storageSuffix: $0.storageSuffix
                    )
                }
                let attachmentMessages = makeMessageFromAttachments(
                    attachments,
                    isModelSupportsVision: modelCapabilities.contains(.visual)
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
                if message.isHistoricalReply {
                    continue
                }
                guard !message.document.isEmpty else { continue }
                requestMessages.append(.assistant(content: .text(message.document)))
            default:
                continue
            }
        }
    }

    func makeMessageFromAttachments(
        _ attachments: [RichEditorView.Object.Attachment],
        isModelSupportsVision: Bool
    ) -> [ChatRequestBody.Message] {
        attachments.compactMap { attach in
            switch attach.type {
            case .image:
                if isModelSupportsVision {
                    guard let image = UIImage(data: attach.imageRepresentation),
                          let base64 = image.pngBase64String(),
                          let url = URL(string: "data:image/png;base64,\(base64)")
                    else {
                        assertionFailure()
                        return nil
                    }
                    if !attach.textRepresentation.isEmpty {
                        return .user(
                            content: .parts([
                                .imageURL(url),
                                .text(attach.textRepresentation),
                            ])
                        )
                    } else {
                        return .user(content: .parts([.imageURL(url)]))
                    }
                } else {
                    guard !attach.textRepresentation.isEmpty else {
                        logger.info("[-] image attachment ignored because not processed")
                        return nil
                    }
                    return .user(content: .text(["[\(attach.name)]", attach.textRepresentation].joined(separator: "\n")))
                }
            case .text:
                return .user(content: .text(["[\(attach.name)]", attach.textRepresentation].joined(separator: "\n")))
            }
        }
    }
}

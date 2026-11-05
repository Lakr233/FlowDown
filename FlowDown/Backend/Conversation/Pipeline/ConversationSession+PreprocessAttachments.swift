//
//  ConversationSession+PreprocessAttachments.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    static let visualInputUnsupportedTitle: String.LocalizationValue = "The selected model does not support image inputs."
    static let visualInputUnsupportedMessage: String.LocalizationValue = "Switch to a model with visual capability to send images."

    /// Title and message of the hint as one sentence pair, for VoiceOver and the message list.
    static var visualInputUnsupportedHintText: String {
        joinedSentences(
            String(localized: visualInputUnsupportedTitle),
            String(localized: visualInputUnsupportedMessage),
        )
    }

    /// Full-width punctuation (Chinese, Japanese) ends a sentence without a
    /// following space; other languages separate sentences with one.
    static func joinedSentences(_ first: String, _ second: String) -> String {
        let fullWidthEnd = first.last.map { "。！？".contains($0) } ?? false
        return first + (fullWidthEnd ? "" : " ") + second
    }

    /// An image only reaches a model as pixels; one without a stored text
    /// description is dropped for a model that cannot read images.
    static func requiresVisualInput(_ attachment: RichEditorView.Object.Attachment) -> Bool {
        attachment.type == .image
            && attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func hasImagesRequiringVisualInput(
        _ attachments: [RichEditorView.Object.Attachment],
        modelCapabilities: Set<ModelCapabilities>,
    ) -> Bool {
        guard !modelCapabilities.contains(.visual) else { return false }
        return attachments.contains(where: requiresVisualInput)
    }

    /// Images go straight to a vision model. A model without vision gets no
    /// image and no separate recognition step; the conversation shows a hint
    /// instead so the image is never dropped silently.
    func noteImagesRequiringVisualInput(
        _ attachments: [RichEditorView.Object.Attachment],
        modelCapabilities: Set<ModelCapabilities>,
    ) async {
        guard Self.hasImagesRequiringVisualInput(attachments, modelCapabilities: modelCapabilities) else { return }
        let count = attachments.filter(Self.requiresVisualInput).count
        Logger.app.infoFile("skipping \(count) image attachment(s): model does not support visual input")
        let hintMessage = appendNewMessage(role: .hint)
        hintMessage.update(\.document, to: Self.visualInputUnsupportedHintText)
        await requestUpdate()
    }
}

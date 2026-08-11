//
//  ConversationSession+PreprocessAttachments.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Combine
import Foundation
import Storage

extension ConversationSession {
    func preprocessAttachments(
        _ object: inout RichEditorView.Object,
        _ modelSupportsVisualInput: Bool,
        _ currentMessageListView: MessageListView,
        _ userMessage: Message,
    ) async throws {
        let skipImageRecognition = ModelManager.shared.defaultModelForAuxiliaryVisualTaskSkipIfPossible
            && modelSupportsVisualInput

        func requiresRecognition(_ attachment: RichEditorView.Object.Attachment) -> Bool {
            attachment.type == .image
                && attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        let attachmentThatRequiresProcess = object.attachments.filter(requiresRecognition)

        guard attachmentThatRequiresProcess.count > 0, !skipImageRecognition else {
            Logger.app.infoFile("requires to process \(attachmentThatRequiresProcess.count) attachments but skipImageRecognition is \(skipImageRecognition)")
            return
        }

        var processCount = 0
        for idx in 0 ..< object.attachments.count
            where requiresRecognition(object.attachments[idx])
        {
            let attach = object.attachments[idx]
            processCount += 1

            // describe the image into text
            guard let image = UIImage(data: attach.imageRepresentation) else {
                assertionFailure()
                continue
            }
            let hint = String(localized: "Identifying an image: \(processCount)/\(attachmentThatRequiresProcess.count)")
            showActivity(hint)
            let text = try await self.processImageToText(
                image: image,
                currentMessageListView,
            )
            object.attachments[idx].textRepresentation = text
        }

        if processCount > 0 {
            showActivity(String(localized: "Processed \(processCount) image(s)"))
        }

        updateAttachments(object.attachments, for: userMessage)
    }
}

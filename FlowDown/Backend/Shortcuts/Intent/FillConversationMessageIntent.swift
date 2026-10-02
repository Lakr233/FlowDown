//
//  FillConversationMessageIntent.swift
//  FlowDown
//
//  Created by qaq on 12/11/2025.
//

import AppIntents
import Foundation
import Storage
import UIKit

struct FillConversationMessageIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Fill Conversation Message"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Add text, images, or audio to the rich editor's temporary storage for the selected conversation."),
            categoryName: LocalizedStringResource("Conversations"),
        )
    }

    @Parameter(title: "Conversation")
    var conversation: ShortcutsEntities.ConversationEntity

    @Parameter(title: "Text", default: "")
    var text: String

    @Parameter(title: "Images")
    var images: [IntentFile]?

    @Parameter(title: "Audio")
    var audio: IntentFile?

    static var parameterSummary: some ParameterSummary {
        Summary("Fill message for \(\.$conversation)") {
            \.$conversation
            \.$text
            \.$images
            \.$audio
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await performInMainThread()

        let message = String(localized: "Message filled successfully")
        let dialog = IntentDialog(.init(stringLiteral: message))
        return .result(dialog: dialog)
    }

    @MainActor
    private func performInMainThread() async throws {
        let identifier = conversation.id

        guard sdb.conversationWith(identifier: identifier) != nil else {
            throw ShortcutUtilitiesError.conversationNotFound
        }

        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let storage = TemporaryStorage(id: identifier)
        let storageDirectory = storage.storageDir

        var attachmentsToAppend: [RichEditorView.Object.Attachment] = []

        if let images, !images.isEmpty {
            for file in images {
                let data = file.data
                guard let image = UIImage(data: data) else { continue }
                if let attachment = RichEditorView.Object.Attachment(image: image, storage: storage) {
                    attachmentsToAppend.append(attachment)
                }
            }
        }

        if let audio {
            let data = audio.data
            let filename = audio.filename.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let fileExtension = filename.flatMap { name -> String? in
                let ext = URL(fileURLWithPath: name).pathExtension
                return ext.isEmpty ? nil : ext
            }
            let transcoded = try await AudioTranscoder.transcode(
                data: data,
                fileExtension: fileExtension,
                output: .mediumQualityM4A,
            )
            let attachment = try await RichEditorView.Object.Attachment.makeAudioAttachment(
                transcoded: transcoded,
                storage: storage,
                suggestedName: filename,
            )
            attachmentsToAppend.append(attachment)
        }

        var editorObject = ConversationManager.shared.getRichEditorObject(identifier: identifier)
            ?? RichEditorView.Object()

        if !trimmedText.isEmpty {
            if editorObject.text.isEmpty {
                editorObject.text = trimmedText
            } else {
                editorObject.text += "\n" + trimmedText
            }
        }

        if !attachmentsToAppend.isEmpty {
            editorObject.attachments.append(contentsOf: attachmentsToAppend)
        }

        if editorObject.options[.storagePrefix] == nil {
            editorObject.options[.storagePrefix] = .url(storageDirectory)
        }

        ConversationManager.shared.setRichEditorObject(identifier: identifier, editorObject)
        NotificationCenter.default.post(
            name: NSNotification.Name("RefreshRichEditor"),
            object: identifier,
        )
    }
}

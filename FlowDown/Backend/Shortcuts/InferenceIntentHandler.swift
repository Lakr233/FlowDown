//
//  InferenceIntentHandler.swift
//  FlowDown
//
//  Created by qaq on 4/11/2025.
//

import AppIntents
import ChatClientKit
import Foundation
import RichEditor
import Storage
import UIKit

enum InferenceIntentHandler {
    struct Options {
        let allowsImages: Bool
        let saveToConversation: Bool
        let enableMemory: Bool

        init(allowsImages: Bool, saveToConversation: Bool = false, enableMemory: Bool = false) {
            self.allowsImages = allowsImages
            self.saveToConversation = saveToConversation
            self.enableMemory = enableMemory
        }
    }

    private struct PreparedImageResources {
        let contentPart: ChatRequestBody.Message.ContentPart
        let attachment: RichEditorView.Object.Attachment
    }

    static func execute(
        model: ShortcutsEntities.ModelEntity?,
        message: String,
        image: IntentFile?,
        options: Options
    ) async throws -> String {
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = image != nil

        if trimmedMessage.isEmpty, !(options.allowsImages && hasImage) {
            throw ShortcutError.emptyMessage
        }

        let modelIdentifier = try resolveModelIdentifier(model: model)
        let modelCapabilities = await MainActor.run {
            ModelManager.shared.modelCapabilities(identifier: modelIdentifier)
        }
        let prompt = preparePrompt()

        var requestMessages: [ChatRequestBody.Message] = []
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.append(.system(content: .text(prompt)))
        }

        var proactiveMemoryProvided = false
        var memoryWritingTools: [ModelTool] = []
        if options.enableMemory {
            if let memoryContext = await MemoryStore.shared.formattedProactiveMemoryContext(),
               !memoryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                proactiveMemoryProvided = true
                requestMessages.append(.system(content: .text(memoryContext)))
            }
            if modelCapabilities.contains(.tool) {
                let guidance = memoryToolGuidance(proactiveMemoryProvided: proactiveMemoryProvided)
                requestMessages.append(.system(content: .text(guidance)))
                memoryWritingTools = allWritingMemoryTools()
            }
        }

        var attachmentsForConversation: [RichEditorView.Object.Attachment] = []
        var contentParts: [ChatRequestBody.Message.ContentPart] = []
        if let image {
            guard options.allowsImages else { throw ShortcutError.imageNotAllowed }
            guard modelCapabilities.contains(.visual) else { throw ShortcutError.imageNotSupportedByModel }
            let resources = try prepareImageResources(from: image)
            contentParts.append(resources.contentPart)
            attachmentsForConversation.append(resources.attachment)
        }

        let userMessage: ChatRequestBody.Message
        if !trimmedMessage.isEmpty {
            if contentParts.isEmpty {
                userMessage = .user(content: .text(trimmedMessage))
            } else {
                contentParts.append(.text(trimmedMessage))
                userMessage = .user(content: .parts(contentParts))
            }
        } else if !contentParts.isEmpty {
            userMessage = .user(content: .parts(contentParts))
        } else {
            throw ShortcutError.emptyMessage
        }

        requestMessages.append(userMessage)

        let toolDefinitions = memoryWritingTools.isEmpty ? nil : memoryWritingTools.map(\.definition)
        let inference = try await ModelManager.shared.infer(
            with: modelIdentifier,
            input: requestMessages,
            tools: toolDefinitions
        )

        let trimmedContent = inference.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = inference.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        let response = trimmedContent.isEmpty ? trimmedReasoning : trimmedContent

        guard !response.isEmpty else { throw ShortcutError.emptyResponse }

        if options.enableMemory,
           modelCapabilities.contains(.tool),
           !memoryWritingTools.isEmpty,
           !inference.toolCallRequests.isEmpty
        {
            await executeMemoryWritingToolCalls(inference.toolCallRequests, using: memoryWritingTools)
        }

        if options.saveToConversation {
            await persistQuickReplyConversation(
                modelIdentifier: modelIdentifier,
                userMessage: trimmedMessage,
                attachments: attachmentsForConversation,
                response: response,
                reasoning: trimmedReasoning
            )
        }

        return response
    }

    static func resolveModelIdentifier(model: ShortcutsEntities.ModelEntity?) throws -> ModelManager.ModelIdentifier {
        if let model {
            return model.id
        }

        let manager = ModelManager.shared

        let defaultConversationModel = ModelManager.ModelIdentifier.defaultModelForConversation
        if !defaultConversationModel.isEmpty {
            return defaultConversationModel
        }

        if let firstCloud = manager.cloudModels.value.first(where: { !$0.id.isEmpty })?.id {
            return firstCloud
        }

        if let firstLocal = manager.localModels.value.first(where: { !$0.id.isEmpty })?.id {
            return firstLocal
        }

        if #available(iOS 26.0, macCatalyst 26.0, *), AppleIntelligenceModel.shared.isAvailable {
            return AppleIntelligenceModel.shared.modelIdentifier
        }

        throw ShortcutError.modelUnavailable
    }

    static func preparePrompt() -> String {
        let manager = ModelManager.shared
        var prompt = manager.defaultPrompt.createPrompt()
        let additional = manager.additionalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !additional.isEmpty {
            if prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prompt = additional
            } else {
                prompt += "\n" + additional
            }
        }
        return prompt
    }

    private static func prepareImageResources(from file: IntentFile) throws -> PreparedImageResources {
        var data = file.data
        if data.isEmpty, let url = file.fileURL {
            data = try Data(contentsOf: url)
        }

        guard !data.isEmpty, let image = UIImage(data: data) else {
            throw ShortcutError.invalidImage
        }

        let processedForRequest = resize(image: image, maxDimension: 1024)
        guard let pngData = processedForRequest.pngData() else {
            throw ShortcutError.invalidImage
        }

        let base64 = pngData.base64EncodedString()
        guard let url = URL(string: "data:image/png;base64,\(base64)") else {
            throw ShortcutError.invalidImage
        }

        let previewImage = resize(image: image, maxDimension: 320)
        let previewData = previewImage.pngData() ?? Data()
        let attachmentName = file.filename.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "Image")

        let attachment = RichEditorView.Object.Attachment(
            type: .image,
            name: attachmentName,
            previewImage: previewData,
            imageRepresentation: data,
            textRepresentation: "",
            storageSuffix: UUID().uuidString
        )

        return PreparedImageResources(contentPart: .imageURL(url), attachment: attachment)
    }

    static func resize(image: UIImage, maxDimension: CGFloat) -> UIImage {
        let largestSide = max(image.size.width, image.size.height)
        guard largestSide > maxDimension else { return image }

        let scale = maxDimension / largestSide
        let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        UIGraphicsBeginImageContextWithOptions(newSize, false, 1)
        defer { UIGraphicsEndImageContext() }
        image.draw(in: CGRect(origin: .zero, size: newSize))
        return UIGraphicsGetImageFromCurrentImageContext() ?? image
    }

    @MainActor
    private static func persistQuickReplyConversation(
        modelIdentifier: ModelManager.ModelIdentifier,
        userMessage: String,
        attachments: [RichEditorView.Object.Attachment],
        response: String,
        reasoning: String
    ) {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMdd-HHmm"
        let suffix = formatter.string(from: Date())

        let titleFormat = String(
            localized: "Quick Reply %@"
        )
        let title = String(format: titleFormat, suffix)

        let iconData = "💨".textToImage(size: 128)?.pngData() ?? Data()

        let conversation = ConversationManager.shared.createNewConversation { conv in
            conv.update(\.icon, to: iconData)
            conv.update(\.title, to: title)
            conv.update(\.shouldAutoRename, to: false)
            if !modelIdentifier.isEmpty {
                conv.update(\.modelId, to: modelIdentifier)
            }
        }

        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let userContent = userMessage.isEmpty
            ? String(localized: "Attachment shared via Shortcut.")
            : userMessage

        let userMessageObject = session.appendNewMessage(role: .user) {
            $0.update(\.document, to: userContent)
        }

        if !attachments.isEmpty {
            session.addAttachments(attachments, to: userMessageObject)
        }

        session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: response)
            if !reasoning.isEmpty {
                $0.update(\.reasoningContent, to: reasoning)
            }
        }

        session.save()
        session.notifyMessagesDidChange()
    }

    private static func memoryToolGuidance(proactiveMemoryProvided: Bool) -> String {
        var guidance = String(localized:
            """
            The system provides several tools for your convenience. Please use them wisely and according to the user's query. Avoid requesting information that is already provided or easily inferred.
            """
        )

        guidance += "\n\n" + MemoryStore.memoryToolsPrompt

        if proactiveMemoryProvided {
            guidance += "\n\n" + String(localized: "A proactive memory summary has been provided above according to the user's setting. Treat it as reliable context and keep it updated through memory tools when necessary.")
        }

        return guidance
    }

    private static func allWritingMemoryTools() -> [ModelTool] {
        ModelToolsManager.shared.tools.filter { tool in
            guard tool.isEnabled else { return false }
            return switch tool {
            case is MTStoreMemoryTool,
                 is MTUpdateMemoryTool,
                 is MTDeleteMemoryTool:
                true
            default:
                false
            }
        }
    }

    private static func executeMemoryWritingToolCalls(_ toolCalls: [ToolCallRequest], using tools: [ModelTool]) async {
        guard !toolCalls.isEmpty else { return }
        let mapping = Dictionary(uniqueKeysWithValues: tools.map { ($0.functionName.lowercased(), $0) })

        for call in toolCalls {
            guard let tool = mapping[call.name.lowercased()] else { continue }
            do {
                _ = try await tool.execute(with: call.args, anchorTo: UIView())
            } catch {
                Logger.model.errorFile("Memory tool \(tool.functionName) failed: \(error.localizedDescription)")
            }
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

//
//  InferenceIntentHandler.swift
//  FlowDown
//
//  Created by qaq on 4/11/2025.
//

import AppIntents
import ChatClientKit
import Foundation
import Storage
import UIKit
import UniformTypeIdentifiers

enum InferenceIntentHandler {
    struct Options {
        let allowsImages: Bool
        let allowsAudio: Bool
        let saveToConversation: Bool
        let enableMemory: Bool
        /// When set, the model must answer through this single tool; the
        /// returned value is the raw JSON arguments of that call. Requires a
        /// model with tool call capability and bypasses memory tools.
        let forcedTool: ChatRequestBody.Tool?

        init(
            allowsImages: Bool,
            allowsAudio: Bool = false,
            saveToConversation: Bool = false,
            enableMemory: Bool = false,
            forcedTool: ChatRequestBody.Tool? = nil,
        ) {
            self.allowsImages = allowsImages
            self.allowsAudio = allowsAudio
            self.saveToConversation = saveToConversation
            self.enableMemory = enableMemory
            self.forcedTool = forcedTool
        }
    }

    struct Dependencies {
        var resolveModelIdentifier: (ShortcutsEntities.ModelEntity?) throws -> ModelManager.ModelIdentifier = {
            try InferenceIntentHandler.resolveModelIdentifier(model: $0)
        }

        var modelCapabilities: (ModelManager.ModelIdentifier) -> Set<ModelCapabilities> = {
            ModelManager.shared.modelCapabilities(identifier: $0)
        }

        var preparePrompt: () -> String = {
            InferenceIntentHandler.preparePrompt()
        }

        var enabledToolsProvider: () -> [ModelTool] = {
            ModelToolsManager.shared.enabledTools
        }

        var shouldExposeMemory: (Bool, [ModelTool]) -> Bool = { modelWillExecuteTools, enabledTools in
            ModelToolsManager.shouldExposeMemory(
                modelWillExecuteTools: modelWillExecuteTools,
                enabledTools: enabledTools,
            )
        }

        var proactiveMemoryContextProvider: () async -> String? = {
            await MemoryStore.shared.formattedProactiveMemoryContext()
        }

        var memoryWritingToolsProvider: () -> [ModelTool] = {
            InferenceIntentHandler.allWritingMemoryTools()
        }

        var streamingInfer: (ModelManager.ModelIdentifier, [ChatRequestBody.Message], [ChatRequestBody.Tool]?, ChatRequestBody.ToolChoice?) async throws -> AsyncThrowingStream<ChatResponseChunk, Error> = { modelID, input, tools, toolChoice in
            try await ModelManager.shared.streamingInfer(
                with: modelID,
                input: input,
                tools: tools,
                toolChoice: toolChoice,
            )
        }

        var executeMemoryWritingToolCalls: ([ToolRequest], [ModelTool]) async -> Void = { toolCalls, tools in
            await InferenceIntentHandler.executeMemoryWritingToolCalls(toolCalls, using: tools)
        }

        var persistConversation: @MainActor (
            ModelManager.ModelIdentifier,
            String,
            [RichEditorView.Object.Attachment],
            String,
            String,
            Date,
        ) -> Void = { modelIdentifier, userMessage, attachments, response, reasoning, date in
            InferenceIntentHandler.persistQuickReplyConversation(
                modelIdentifier: modelIdentifier,
                userMessage: userMessage,
                attachments: attachments,
                response: response,
                reasoning: reasoning,
                date: date,
            )
        }

        var clock: () -> Date = { Date() }

        static var live: Self {
            .init()
        }
    }

    private struct PreparedImageResources {
        let contentPart: ChatRequestBody.Message.ContentPart
        let attachment: RichEditorView.Object.Attachment
    }

    private struct PreparedAudioResources {
        let contentParts: [ChatRequestBody.Message.ContentPart]
        let attachment: RichEditorView.Object.Attachment
    }

    static var defaultDependencies: Dependencies = .live

    static func execute(
        model: ShortcutsEntities.ModelEntity?,
        message: String,
        image: IntentFile?,
        audio: IntentFile?,
        options: Options,
        dependencies: Dependencies? = nil,
    ) async throws -> String {
        let dependencies = dependencies ?? defaultDependencies
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasImage = image != nil
        let hasAudio = audio != nil

        if trimmedMessage.isEmpty,
           !(options.allowsImages && hasImage),
           !(options.allowsAudio && hasAudio)
        {
            throw ShortcutError.emptyMessage
        }

        let modelIdentifier = try dependencies.resolveModelIdentifier(model)
        let modelCapabilities = await MainActor.run {
            dependencies.modelCapabilities(modelIdentifier)
        }
        if options.forcedTool != nil, !modelCapabilities.contains(.tool) {
            throw ShortcutError.toolCallNotSupportedByModel
        }
        let prompt = dependencies.preparePrompt()

        var requestMessages: [ChatRequestBody.Message] = []
        if !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            requestMessages.append(.system(content: .text(prompt)))
        }

        var proactiveMemoryProvided = false
        var memoryWritingTools: [ModelTool] = []
        let enabledTools = dependencies.enabledToolsProvider()
        let shouldExposeMemory = options.forcedTool == nil
            && dependencies.shouldExposeMemory(options.enableMemory, enabledTools)

        if shouldExposeMemory {
            if let memoryContext = await dependencies.proactiveMemoryContextProvider(),
               !memoryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                proactiveMemoryProvided = true
                requestMessages.append(.system(content: .text(memoryContext)))
            }
            if modelCapabilities.contains(.tool) {
                let guidance = memoryToolGuidance(proactiveMemoryProvided: proactiveMemoryProvided)
                requestMessages.append(.system(content: .text(guidance)))
                memoryWritingTools = dependencies.memoryWritingToolsProvider()
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
        if let audio {
            guard options.allowsAudio else { throw ShortcutError.audioNotAllowed }
            guard modelCapabilities.contains(.auditory) else { throw ShortcutError.audioNotSupportedByModel }
            let resources = try await prepareAudioResources(from: audio)
            contentParts.append(contentsOf: resources.contentParts)
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

        var toolDefinitions = memoryWritingTools.isEmpty ? nil : memoryWritingTools.map(\.definition)
        var toolChoice: ChatRequestBody.ToolChoice?
        if let forcedTool = options.forcedTool {
            toolDefinitions = [forcedTool]
            switch forcedTool {
            case let .function(name, _, _, _):
                toolChoice = .function(name: name)
            }
        }
        let inference = try await dependencies.streamingInfer(modelIdentifier, requestMessages, toolDefinitions, toolChoice)

        var content = ""
        var reasoningContent = ""
        var toolRequests: [ToolRequest] = []
        for try await chunk in inference {
            switch chunk {
            case let .text(value):
                content += value
            case let .reasoning(value):
                reasoningContent += value
            case let .tool(call):
                toolRequests.append(call)
            case .image:
                break
            }
        }

        if let forcedTool = options.forcedTool {
            guard case let .function(forcedName, _, _, _) = forcedTool,
                  let call = toolRequests.first(where: { $0.name == forcedName })
            else {
                throw ShortcutError.emptyResponse
            }
            return call.args
        }

        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedReasoning = reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
        var response = trimmedContent.isEmpty ? trimmedReasoning : trimmedContent

        #if DEBUG
            print("Inference response: \(response)")
            print("Tool requests: \(toolRequests)")
        #endif

        if response.isEmpty {
            if toolRequests.isEmpty {
                throw ShortcutError.emptyResponse
            } else {
                response = String(localized: "Executed \(toolRequests.count) tool calls")
            }
        }

        if shouldExposeMemory,
           modelCapabilities.contains(.tool),
           !memoryWritingTools.isEmpty,
           !toolRequests.isEmpty
        {
            await dependencies.executeMemoryWritingToolCalls(toolRequests, memoryWritingTools)
        }

        if options.saveToConversation {
            let now = dependencies.clock()
            let attachments = attachmentsForConversation
            let responseToPersist = response
            await dependencies.persistConversation(
                modelIdentifier,
                trimmedMessage,
                attachments,
                responseToPersist,
                trimmedReasoning,
                now,
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

        // Compress and normalize before sending or storing
        let compressedData = image.prepareAttachment() ?? data
        guard let compressedImage = UIImage(data: compressedData) else {
            throw ShortcutError.invalidImage
        }

        let processedForRequest = resize(image: compressedImage, maxDimension: 1024)
        let requestData: Data
        let mimeType: String
        if let jpegData = processedForRequest.jpegData(compressionQuality: 0.8) {
            requestData = jpegData
            mimeType = "image/jpeg"
        } else if let pngData = processedForRequest.pngData() {
            requestData = pngData
            mimeType = "image/png"
        } else {
            throw ShortcutError.invalidImage
        }

        let base64 = requestData.base64EncodedString()
        guard let url = URL(string: "data:\(mimeType);base64,\(base64)") else {
            throw ShortcutError.invalidImage
        }

        let previewImage = resize(image: compressedImage, maxDimension: 320)
        let previewData = previewImage.jpegData(compressionQuality: 0.7)
            ?? previewImage.pngData()
            ?? Data()
        let attachmentName = file.filename.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "Image")

        let attachment = RichEditorView.Object.Attachment(
            type: .image,
            name: attachmentName,
            previewImage: previewData,
            imageRepresentation: compressedData,
            textRepresentation: "",
            storageSuffix: UUID().uuidString,
        )

        return PreparedImageResources(contentPart: .imageURL(url), attachment: attachment)
    }

    private static func prepareAudioResources(from file: IntentFile) async throws -> PreparedAudioResources {
        var data = file.data
        if data.isEmpty, let url = file.fileURL {
            data = try Data(contentsOf: url)
        }

        guard !data.isEmpty else {
            throw ShortcutError.invalidAudio
        }

        let transcoded = try await AudioTranscoder.transcode(
            data: data,
            fileExtension: inferredAudioFileExtension(from: file),
            output: .compressedQualityWAV,
        )
        let format = transcoded.format.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty?.lowercased() ?? "wav"
        let attachment = try await RichEditorView.Object.Attachment.makeAudioAttachment(
            transcoded: transcoded,
            storage: nil,
            suggestedName: file.filename.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
        )
        let base64 = transcoded.data.base64EncodedString()

        var metadataLines = ["[\(attachment.name)]"]
        let details = attachment.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
        if !details.isEmpty {
            metadataLines.append(details)
        }

        let contentParts: [ChatRequestBody.Message.ContentPart] = [
            .audioBase64(base64, format: format),
            .text(metadataLines.joined(separator: "\n")),
        ]

        return PreparedAudioResources(contentParts: contentParts, attachment: attachment)
    }

    private static func inferredAudioFileExtension(from file: IntentFile) -> String? {
        if let url = file.fileURL {
            let ext = url.pathExtension.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ext.isEmpty {
                return ext
            }
        }

        let filename = file.filename.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dotIndex = filename.lastIndex(of: "."),
              dotIndex < filename.index(before: filename.endIndex)
        else { return nil }

        let suffixStart = filename.index(after: dotIndex)
        let ext = filename[suffixStart...].trimmingCharacters(in: .whitespacesAndNewlines)
        return ext.isEmpty ? nil : ext
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
        reasoning: String,
        date: Date,
    ) {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let suffix = formatter.string(from: date)

        let titleFormat = String(
            localized: "Quick Reply %@",
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
        let collapseAfterReasoningComplete = ModelManager.shared.collapseReasoningSectionWhenComplete

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
                if collapseAfterReasoningComplete {
                    $0.update(\.isThinkingFold, to: true)
                }
            }
        }

        session.save()
        session.notifyMessagesDidChange()
    }

    private static func memoryToolGuidance(proactiveMemoryProvided: Bool) -> String {
        var guidance = String(localized:
            """
            Use the provided tools when they fit the user's request. Don't look up what is already given or easily inferred.
            """)

        guidance += "\n\n" + MemoryStore.memoryToolsPrompt

        if proactiveMemoryProvided {
            guidance += "\n\n" + String(localized: "The memory summary above follows the user's settings. Treat it as reliable and keep it current with the memory tools.")
        }

        return guidance
    }

    private static func allWritingMemoryTools() -> [ModelTool] {
        ModelToolsManager.shared.enabledMemoryWritingTools
    }

    private static func executeMemoryWritingToolCalls(_ toolCalls: [ToolRequest], using tools: [ModelTool]) async {
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

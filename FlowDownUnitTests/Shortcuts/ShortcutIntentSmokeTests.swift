import AppIntents
import ChatClientKit
@testable import FlowDown
import Foundation
import Storage
import Testing
import UniformTypeIdentifiers

@Suite(.serialized)
struct ShortcutIntentSmokeTests {
    @Test
    @MainActor
    func `create new conversation intent returns the created entity`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let originalShowGuideMessage = ConversationManager.shouldShowGuideMessage
        ConversationManager.shouldShowGuideMessage = false
        defer { ConversationManager.shouldShowGuideMessage = originalShowGuideMessage }

        let intent = CreateNewConversationIntent()
        intent.switchToConversation = false

        let result = try await intent.perform()
        guard let entity = result.value else {
            Issue.record("Expected CreateNewConversationIntent to return a conversation entity.")
            return
        }
        defer {
            ConversationManager.shared.deleteConversation(identifier: entity.id)
        }

        #expect(!entity.id.isEmpty)
        #expect(sdb.conversationWith(identifier: entity.id) != nil)
    }

    @Test
    @MainActor
    func `generate response intent forwards message model and save options to the inference handler`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let recorder = ShortcutIntentRecorder()
        try await withShortcutDependencies(
            makeShortcutDependencies(
                recorder: recorder,
                modelCapabilities: [],
                responseText: "Generated reply",
            ),
        ) {
            let intent = GenerateResponseIntent()
            intent.model = .init(
                id: "shortcut-model",
                displayName: "Shortcut Model",
                source: .cloud,
            )
            intent.message = "Hello FlowDown"
            intent.saveToConversation = true
            intent.enableMemory = true

            let result = try await intent.perform()
            let persisted = recorder.persisted.first
            let userText = userText(in: recorder.streamedMessages.first ?? [])

            #expect(result.value == "Generated reply")
            #expect(recorder.resolvedModel?.id == "shortcut-model")
            #expect(recorder.shouldExposeMemoryCalls == [true])
            #expect(userText == "Hello FlowDown")
            #expect(persisted?.modelIdentifier == "shortcut-model")
            #expect(persisted?.userMessage == "Hello FlowDown")
            #expect(persisted?.attachments.count == 0)
            #expect(persisted?.response == "Generated reply")
        }
    }

    @Test
    @MainActor
    func `search conversations intent formats matching conversations and normalizes result limits`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let unique = UUID().uuidString
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Shortcut Search \(unique)")
        }
        defer {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        }

        let userMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .user)
            message.update(\.document, to: "Need summary for \(unique)")
        }
        let assistantMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .assistant)
            message.update(\.document, to: "Prepared summary for \(unique)")
        }
        sdb.messagePut(messages: [userMessage, assistantMessage])

        let intent = SearchConversationsIntent()
        intent.keyword = unique
        intent.resultLimit = 0

        let result = try await intent.perform()
        let values = result.value ?? []

        #expect(values.count == 1)
        #expect(values[0].contains("Shortcut Search \(unique)"))
        #expect(values[0].contains("Need summary for \(unique)"))
        #expect(values[0].contains("Prepared summary for \(unique)"))
    }

    @Test
    @MainActor
    func `summarize intent wraps source text in the summarization directive`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let recorder = ShortcutIntentRecorder()
        try await withShortcutDependencies(
            makeShortcutDependencies(
                recorder: recorder,
                modelCapabilities: [],
                responseText: "Short summary",
            ),
        ) {
            let intent = SummarizeTextIntent()
            intent.text = "Long article body"

            let result = try await intent.perform()
            let userText = userText(in: recorder.streamedMessages.first ?? [])

            #expect(result.value == "Short summary")
            #expect(userText?.contains("Long article body") == true)
        }
    }

    @Test
    @MainActor
    func `translate text intent injects the selected target language into the prompt`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let recorder = ShortcutIntentRecorder()
        try await withShortcutDependencies(
            makeShortcutDependencies(
                recorder: recorder,
                modelCapabilities: [],
                responseText: "Hallo Welt",
            ),
        ) {
            let intent = TranslateTextIntent()
            intent.text = "Hello world"
            intent.targetLanguage = .german

            let result = try await intent.perform()
            let userText = userText(in: recorder.streamedMessages.first ?? [])

            #expect(result.value == "Hallo Welt")
            #expect(userText?.contains("translate the input text into Deutsch") == true)
            #expect(userText?.contains("Hello world") == true)
        }
    }

    @Test
    @MainActor
    func `transcribe audio intent forwards audio content language hint and save option`() async throws {
        guard #available(iOS 18.0, macCatalyst 18.0, *) else {
            return
        }
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let recorder = ShortcutIntentRecorder()
        try await withShortcutDependencies(
            makeShortcutDependencies(
                recorder: recorder,
                modelCapabilities: [.auditory],
                responseText: "Transcribed speech",
            ),
        ) {
            let intent = TranscribeAudioIntent()
            intent.model = .init(
                id: "audio-model",
                displayName: "Audio Model",
                source: .cloud,
            )
            intent.audio = IntentFile(
                data: makeWAVData(sampleRate: 16000, channelCount: 1, duration: 0.1),
                filename: "sample.wav",
                type: .wav,
            )
            intent.languageHint = "Japanese"
            intent.saveToConversation = true

            let result = try await intent.perform()
            let streamedMessages = recorder.streamedMessages.first ?? []
            let userParts = userContentParts(in: streamedMessages)
            let persisted = recorder.persisted.first

            #expect(result.value == "Transcribed speech")
            #expect(recorder.resolvedModel?.id == "audio-model")
            #expect(userParts?.contains(where: {
                if case .audioBase64 = $0 { return true }
                return false
            }) == true)
            #expect(userParts?.contains(where: {
                if case let .text(text) = $0 {
                    return text.contains("Japanese")
                }
                return false
            }) == true)
            #expect(persisted?.modelIdentifier == "audio-model")
            #expect(persisted?.attachments.count == 1)
            #expect(persisted?.response == "Transcribed speech")
        }
    }
}

private extension ShortcutIntentSmokeTests {
    final class ShortcutIntentRecorder {
        struct PersistInvocation {
            let modelIdentifier: String
            let userMessage: String
            let attachments: [RichEditorView.Object.Attachment]
            let response: String
        }

        var resolvedModel: ShortcutsEntities.ModelEntity?
        var streamedMessages: [[ChatRequestBody.Message]] = []
        var shouldExposeMemoryCalls: [Bool] = []
        var persisted: [PersistInvocation] = []
    }

    @MainActor
    func withShortcutDependencies(
        _ dependencies: InferenceIntentHandler.Dependencies,
        body: () async throws -> Void,
    ) async throws {
        let originalDependencies = InferenceIntentHandler.defaultDependencies
        InferenceIntentHandler.defaultDependencies = dependencies
        defer { InferenceIntentHandler.defaultDependencies = originalDependencies }
        try await body()
    }

    func makeShortcutDependencies(
        recorder: ShortcutIntentRecorder,
        modelCapabilities: Set<ModelCapabilities>,
        responseText: String,
    ) -> InferenceIntentHandler.Dependencies {
        var dependencies = InferenceIntentHandler.Dependencies.live
        dependencies.resolveModelIdentifier = { model in
            recorder.resolvedModel = model
            return model?.id ?? "shortcut-default-model"
        }
        dependencies.modelCapabilities = { _ in
            modelCapabilities
        }
        dependencies.preparePrompt = { "" }
        dependencies.enabledToolsProvider = { [] }
        dependencies.shouldExposeMemory = { enabled, _ in
            recorder.shouldExposeMemoryCalls.append(enabled)
            return false
        }
        dependencies.proactiveMemoryContextProvider = { nil }
        dependencies.memoryWritingToolsProvider = { [] }
        dependencies.streamingInfer = { _, messages, _, _ in
            recorder.streamedMessages.append(messages)
            return makeResponseStream([.text(responseText)])
        }
        dependencies.persistConversation = { modelIdentifier, userMessage, attachments, response, _, _ in
            recorder.persisted.append(
                .init(
                    modelIdentifier: modelIdentifier,
                    userMessage: userMessage,
                    attachments: attachments,
                    response: response,
                ),
            )
        }
        return dependencies
    }

    func userText(in messages: [ChatRequestBody.Message]) -> String? {
        guard case let .user(content, _) = messages.last else {
            return nil
        }

        switch content {
        case let .text(text):
            return text
        case let .parts(parts):
            return parts.compactMap {
                if case let .text(text) = $0 {
                    return text
                }
                return nil
            }
            .joined(separator: "\n")
        }
    }

    func userContentParts(in messages: [ChatRequestBody.Message]) -> [ChatRequestBody.Message.ContentPart]? {
        guard case let .user(content, _) = messages.last else {
            return nil
        }

        if case let .parts(parts) = content {
            return parts
        }
        return nil
    }

    func makeWAVData(
        sampleRate: Int,
        channelCount: Int,
        duration: Double,
    ) -> Data {
        let frameCount = max(Int(Double(sampleRate) * duration), 1)
        let bitsPerSample = 16
        let blockAlign = channelCount * (bitsPerSample / 8)
        let byteRate = sampleRate * blockAlign
        let amplitude = Double(Int16.max) * 0.25

        var pcm = Data(capacity: frameCount * blockAlign)
        for frame in 0 ..< frameCount {
            let sample = Int16(
                (sin((2 * .pi * Double(frame) * 440.0) / Double(sampleRate)) * amplitude)
                    .rounded(),
            )
            for _ in 0 ..< channelCount {
                appendUInt16LE(UInt16(bitPattern: sample), to: &pcm)
            }
        }

        var data = Data(capacity: 44 + pcm.count)
        data.append(Data("RIFF".utf8))
        appendUInt32LE(UInt32(36 + pcm.count), to: &data)
        data.append(Data("WAVE".utf8))
        data.append(Data("fmt ".utf8))
        appendUInt32LE(16, to: &data)
        appendUInt16LE(1, to: &data)
        appendUInt16LE(UInt16(channelCount), to: &data)
        appendUInt32LE(UInt32(sampleRate), to: &data)
        appendUInt32LE(UInt32(byteRate), to: &data)
        appendUInt16LE(UInt16(blockAlign), to: &data)
        appendUInt16LE(UInt16(bitsPerSample), to: &data)
        data.append(Data("data".utf8))
        appendUInt32LE(UInt32(pcm.count), to: &data)
        data.append(pcm)
        return data
    }

    func appendUInt16LE(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0x00FF))
        data.append(UInt8((value >> 8) & 0x00FF))
    }

    func appendUInt32LE(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0x0000_00FF))
        data.append(UInt8((value >> 8) & 0x0000_00FF))
        data.append(UInt8((value >> 16) & 0x0000_00FF))
        data.append(UInt8((value >> 24) & 0x0000_00FF))
    }
}

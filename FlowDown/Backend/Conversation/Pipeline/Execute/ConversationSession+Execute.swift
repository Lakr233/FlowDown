//
//  ConversationSession+Execute.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/25/25.
//

import AlertController
import ChatClientKit
import ScrubberKit
import Storage
import UIKit

extension ConversationSession {
    func doInfere(
        modelID: ModelManager.ModelIdentifier,
        inputObject: RichEditorView.Object,
        completion: @escaping () -> Void,
    ) {
        cancelCurrentTask { [self] in
            Logger.app.infoFile("do infere called: \(id)")
            Logger.app.infoFile("    - chat - \(ModelManager.shared.modelName(identifier: models.chat))")
            Logger.app.infoFile("    - task - \(ModelManager.shared.modelName(identifier: models.auxiliary))")

            var backgroundTask: UIBackgroundTaskIdentifier = .invalid
            backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
                if let id = self?.id {
                    Logger.app.errorFile("background task expired for conversation: \(id)")
                } else {
                    Logger.app.errorFile("background task expired for unknown conversation")
                }
                self?.currentTask?.cancel()
                UIApplication.shared.endBackgroundTask(backgroundTask)
                backgroundTask = .invalid
            }

            currentTask = Task {
                await MainActor.run {
                    ConversationSessionManager.shared.markSessionExecuting(id)
                }

                defer {
                    if backgroundTask != .invalid {
                        let finalBackgroundTask = backgroundTask
                        backgroundTask = .invalid
                        Task { @MainActor in
                            UIApplication.shared.endBackgroundTask(finalBackgroundTask)
                        }
                    }
                }

                showActivity()
                await requestUpdate()
                await doInfereExecute(
                    modelID: modelID,
                    inputObject: inputObject,
                )
                self.currentTask = nil
                // Check if there's a pending refresh after task completion
                await MainActor.run {
                    ConversationSessionManager.shared.markSessionCompleted(id)
                    ConversationSessionManager.shared.resolvePendingRefresh(for: id)
                    completion()
                }
            }
        }
    }

    /// Publishes the current message list to the UI. Every mutation inside the
    /// pipeline goes through here so views never read half-written state.
    func requestUpdate() async {
        notifyMessagesDidChange()
    }

    private nonisolated func doInfereExecute(
        modelID: ModelManager.ModelIdentifier,
        inputObject: RichEditorView.Object,
    ) async {
        let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelID)

        assert(models.chat != nil)

        // prevent screen lock
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        save()

        // Build the request from history; attachments still in the editor are added later.
        var requestMessages: [ChatRequestBody.Message] = []
        await buildInitialRequestMessages(&requestMessages, modelCapabilities)

        do {
            try await doInfereExecuteCore(
                inputObject,
                modelCapabilities,
                &requestMessages,
                modelID,
            )
        } catch {
            logger.errorFile("\(error.localizedDescription)")
            finalizeInterruptedReasoning()
            let sanitized = error.localizedDescription
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if error is InferenceUserCancellationError {
                // A cancellation is the user's own doing, not a failure worth an
                // assistant bubble; show it like the date separators do.
                let hintMessage = appendNewMessage(role: .hint)
                hintMessage.update(\.document, to: sanitized)
            } else {
                let errorMessage = appendNewMessage(role: .assistant)
                errorMessage.update(\.document, to: "```\n\(sanitized)")
            }
        }

        stopThinkingForAll()

        await requestUpdate()
        save()

        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
        endActivity()
    }

    /// Gives each assistant message cut off mid-reasoning the placeholder the
    /// completed round writes, so its reasoning still replays with a non-empty
    /// turn. The message list folds the reply into the activity summary and
    /// never shows the placeholder; the summary stops once the session does.
    func finalizeInterruptedReasoning() {
        for message in messages where message.role == .assistant {
            let reasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
            let document = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reasoning.isEmpty, document.isEmpty else { continue }
            message.update(\.document, to: String(localized: "Thinking finished without output any content."))
        }
    }

    /// How many rounds of tool calls one message may run.
    static let toolRoundLimit = 64

    func requestLinkContentIndex(_ url: URL) -> Int {
        assert(!Thread.isMainThread)
        let index = linkedContents.count + 1
        linkedContents[index] = url
        Logger.app.infoFile("request link content index: \(index) for url: \(url)")
        return index
    }

    private func doInfereExecuteCore(
        _ object: RichEditorView.Object,
        _ modelCapabilities: Set<ModelCapabilities>,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelID: ModelManager.ModelIdentifier,
    ) async throws {
        let modelName = ModelManager.shared.modelName(identifier: modelID)
        let modelContextLength = ModelManager.shared.modelContextLength(identifier: modelID)
        let modelWillExecuteTools = if case let .bool(value) = object.options[.tools] { value } else { false }
        if modelWillExecuteTools {
            assert(modelCapabilities.contains(.tool))
        }

        try checkCancellation()
        showActivity()

        let document = object.text
        let userMessage = appendNewMessage(role: .user)
        userMessage.update(\.document, to: document)

        addAttachments(object.attachments, to: userMessage)
        await requestUpdate()

        updateAttachments(object.attachments, for: userMessage)
        save()

        try checkCancellation()
        await noteImagesRequiringVisualInput(
            object.attachments,
            modelCapabilities: modelCapabilities,
        )

        if !object.attachments.isEmpty {
            showActivity(String(localized: "Processing Attachments"))
            let attachmentMessages = await makeMessageFromAttachments(
                object.attachments,
                modelCapabilities: modelCapabilities,
            )
            requestMessages.append(contentsOf: attachmentMessages)
            save()
        }

        let shouldPrepareMCP = MCPService.shared.servers.value.contains(where: \.isEnabled)
        if shouldPrepareMCP {
            showActivity(String(localized: "Preparing Model Context"))
            await MCPService.shared.prepareForConversation { [weak self] status in
                self?.showActivity(status)
            }
            try checkCancellation()
            showActivity(String(localized: "Preparing Model Context"))
        }

        let toolSet: ModelToolSet = modelWillExecuteTools
            ? await ModelToolsManager.shared.makeToolSet()
            : .empty
        let webSearchEnabled = toolSet.contains { $0 is MTWebSearchTool }

        await ConversationSystemPromptBuilder.appendMessages(
            to: &requestMessages,
            input: .init(
                userText: object.text,
                modelName: modelName,
                modelWillExecuteTools: modelWillExecuteTools,
                webSearchEnabled: webSearchEnabled,
                contextPlacement: ConversationSystemPromptBuilder.contextPlacement(for: modelID),
            ),
            dependencies: .live(),
        )

        try checkCancellation()
        if try removeOutOfContextContents(
            &requestMessages,
            toolSet.definitions,
            modelContextLength,
            preservesReasoning: modelCapabilities.contains(.preservedThinking),
        ) {
            let hintMessage = appendNewMessage(role: .hint)
            hintMessage.update(
                \.document,
                to: String(localized: "Some messages have been removed to fit the model context length.")
            )
            await requestUpdate()
        }

        try checkCancellation()
        save()

        var shouldContinue = false
        var toolRounds = 0
        repeat {
            // A round returns true exactly when it executed tools, so the next
            // one is their follow-up even if attachments now end the request.
            let isFollowUpAfterToolCall = shouldContinue
            shouldContinue = try await doMainInferenceOnce(
                modelID,
                &requestMessages,
                toolSet,
                modelWillExecuteTools,
                isFollowUpAfterToolCall,
            )
            save()
            if shouldContinue {
                toolRounds += 1
                // A model that keeps calling tools would otherwise run until
                // the context fills up.
                if toolRounds >= Self.toolRoundLimit {
                    let hintMessage = appendNewMessage(role: .hint)
                    hintMessage.update(
                        \.document,
                        to: String(localized: "Stopped after \(toolRounds) rounds of tool calls."),
                    )
                    await requestUpdate()
                    shouldContinue = false
                }
            }
        } while shouldContinue

        await requestUpdate()

        Logger.app.infoFile("inference done")

        let shouldExtractMemory = modelWillExecuteTools && ModelToolsManager.shared.canStoreMemory
        let recentMessages = Array(messages.suffix(6))
        let auxModel = models.auxiliary
        let convId = id
        let allMessages = messages
        await MainActor.run {
            _ = Task {
                if shouldExtractMemory {
                    await MemoryExtractor.shared.extractIfNeeded(
                        from: recentMessages,
                        conversationId: convId.description,
                        using: auxModel,
                    )
                }
                await ConversationSummarizer.shared.summarizeIfNeeded(
                    conversationId: convId,
                    messages: allMessages,
                    using: auxModel,
                )
            }
        }

        try checkCancellation()
        if shouldAutoRename {
            await updateTitleAndIcon()
        }
    }
}

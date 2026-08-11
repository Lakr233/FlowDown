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
        currentMessageListView: MessageListView,
        inputObject: RichEditorView.Object,
        completion: @escaping () -> Void,
    ) {
        cancelCurrentTask { [self] in
            Logger.app.infoFile("do infere called: \(id)")
            Logger.app.infoFile("    - chat - \(ModelManager.shared.modelName(identifier: models.chat))")
            Logger.app.infoFile("    - task - \(ModelManager.shared.modelName(identifier: models.auxiliary))")
            Logger.app.infoFile("    - view - \(ModelManager.shared.modelName(identifier: models.visualAuxiliary))")

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
                await requestUpdate(view: currentMessageListView)
                await doInfereExecute(
                    modelID: modelID,
                    currentMessageListView: currentMessageListView,
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

    func requestUpdate(view _: MessageListView) async {
        notifyMessagesDidChange()
    }

    private nonisolated func doInfereExecute(
        modelID: ModelManager.ModelIdentifier,
        currentMessageListView: MessageListView,
        inputObject: RichEditorView.Object,
    ) async {
        var object = inputObject

        // MARK: - 推理前准备

        let modelName = ModelManager.shared.modelName(identifier: modelID)
        let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelID)
        let modelContextLength = ModelManager.shared.modelContextLength(identifier: modelID)
        var modelWillExecuteTools = false
        if case let .bool(value) = object.options[.tools], value {
            assert(modelCapabilities.contains(.tool))
            modelWillExecuteTools = true
        }

        assert(models.chat != nil)

        // prevent screen lock
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        save()

        // MARK: - 上下文转译到请求体 不包含当前编辑框中的附件

        var requestMessages: [ChatRequestBody.Message] = []
        await buildInitialRequestMessages(&requestMessages, modelCapabilities)

        do {
            try await doInfereExecuteCore(
                currentMessageListView,
                &object,
                modelCapabilities,
                &requestMessages,
                modelName,
                modelWillExecuteTools,
                modelContextLength,
                modelID,
            )
            save()
        } catch {
            logger.errorFile("\(error.localizedDescription)")
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
            await requestUpdate(view: currentMessageListView)
            await requestUpdate(view: currentMessageListView)
        }

        stopThinkingForAll()

        await requestUpdate(view: currentMessageListView)
        save()

        await requestUpdate(view: currentMessageListView)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
        endActivity()
    }

    func requestLinkContentIndex(_ url: URL) -> Int {
        assert(!Thread.isMainThread)
        let index = linkedContents.count + 1
        linkedContents[index] = url
        Logger.app.infoFile("request link content index: \(index) for url: \(url)")
        return index
    }

    private func doInfereExecuteCore(
        _ currentMessageListView: MessageListView,
        _ object: inout RichEditorView.Object,
        _ modelCapabilities: Set<ModelCapabilities>,
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelName: String,
        _ modelWillExecuteTools: Bool,
        _ modelContextLength: Int,
        _ modelID: ModelManager.ModelIdentifier,
    ) async throws {
        try checkCancellation()
        showActivity()

        // MARK: - 添加用户的消息到储存框架

        let document = object.text
        let userMessage = appendNewMessage(role: .user)
        userMessage.update(\.document, to: document)

        addAttachments(object.attachments, to: userMessage)
        await requestUpdate(view: currentMessageListView)

        // MARK: - 添加 Attachment 数据到持久化内容

        updateAttachments(object.attachments, for: userMessage)
        save()

        // MARK: - 预处理图片信息提取

        try checkCancellation()
        try await preprocessAttachments(
            &object,
            modelCapabilities.contains(.visual),
            currentMessageListView,
            userMessage,
        )
        save()

        // MARK: - 添加这次的附件

        if !object.attachments.isEmpty {
            showActivity(String(localized: "Processing Attachments"))
            let attachmentMessages = await makeMessageFromAttachments(
                object.attachments,
                modelCapabilities: modelCapabilities,
            )
            requestMessages.append(contentsOf: attachmentMessages)
            save()
        }

        // MARK: - 构建工具调用列表

        let servers = MCPService.shared.servers.value
        let shouldPrepareMCP = servers.filter(\.isEnabled).count > 0
        if shouldPrepareMCP {
            showActivity(String(localized: "Preparing Model Context"))
            await MCPService.shared.prepareForConversation { [weak self] status in
                self?.showActivity(status)
            }
            try checkCancellation()
            showActivity(String(localized: "Preparing Model Context"))
        }

        var tools: [ModelTool] = []
        if modelWillExecuteTools {
            await tools.append(contentsOf: ModelToolsManager.shared.getEnabledToolsIncludeMCP())
        }

        let toolsDefinitions = tools.isEmpty ? nil : tools.map(\.definition)
        let webSearchEnabled = tools.contains { $0 is MTWebSearchTool }

        // MARK: - 添加最新的系统提示

        await injectNewSystemCommand(
            &requestMessages,
            modelName,
            modelWillExecuteTools,
            webSearchEnabled,
            object,
        )

        // MARK: - 删除超出上下文长度限制的消息

        try checkCancellation()
        if try removeOutOfContextContents(&requestMessages, toolsDefinitions, modelContextLength) {
            let hintMessage = appendNewMessage(role: .hint)
            hintMessage.update(\.document, to: String(localized: "Some messages have been removed to fit the model context length."))
            await requestUpdate(view: currentMessageListView)
        }

        // MARK: - 开始循环调用接口

        try checkCancellation()
        save()

        var shouldContinue = false
        repeat {
            shouldContinue = try await doMainInferenceOnce(
                currentMessageListView,
                modelID,
                &requestMessages,
                toolsDefinitions,
                modelWillExecuteTools,
                linkedContents: linkedContents,
                requestLinkContentIndex: requestLinkContentIndex,
            )
            save()
        } while shouldContinue

        await requestUpdate(view: currentMessageListView)

        Logger.app.infoFile("inference done")

        // MARK: - 自动记忆提取和对话摘要

        let shouldExtractMemory = modelWillExecuteTools && ModelToolsManager.shared.canStoreMemory
        let recentMessages = Array(messages.suffix(6))
        let auxModel = models.auxiliary ?? models.chat
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

        // MARK: - 生成标题和图标

        try checkCancellation()
        if shouldAutoRename {
            await updateTitleAndIcon()
        }
    }
}

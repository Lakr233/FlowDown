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

                await currentMessageListView.loading()
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

    func requestUpdate(view: MessageListView) async {
        await view.stopLoading()
        notifyMessagesDidChange()
    }

    func saveIfNeeded(_ object: RichEditorView.Object) {
        if case let .bool(value) = object.options[.ephemeral], !value {
            save()
        }
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
        var modelWillGoSearchWeb = false
        if case let .bool(value) = object.options[.tools], value {
            assert(modelCapabilities.contains(.tool))
            modelWillExecuteTools = true
        }
        if case let .bool(value) = object.options[.browsing], value {
            modelWillGoSearchWeb = true
        }

        assert(models.chat != nil)

        // prevent screen lock
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = true }
        saveIfNeeded(object)

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
                modelWillGoSearchWeb,
                modelContextLength,
                modelID,
            )
            saveIfNeeded(object)
        } catch {
            logger.errorFile("\(error.localizedDescription)")
            let errorMessage = appendNewMessage(role: .assistant)
            let sanitized = error.localizedDescription
                .trimmingCharacters(in: .whitespacesAndNewlines)
            errorMessage.update(\.document, to: "```\n\(sanitized)")
            await requestUpdate(view: currentMessageListView)
            await requestUpdate(view: currentMessageListView)
        }

        stopThinkingForAll()

        await requestUpdate(view: currentMessageListView)
        saveIfNeeded(object)

        await requestUpdate(view: currentMessageListView)
        await MainActor.run { UIApplication.shared.isIdleTimerDisabled = false }
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
        _ modelWillGoSearchWeb: Bool,
        _ modelContextLength: Int,
        _ modelID: ModelManager.ModelIdentifier,
    ) async throws {
        try checkCancellation()
        await currentMessageListView.loading()

        // MARK: - 添加用户的消息到储存框架

        let document = object.text
        let userMessage = appendNewMessage(role: .user)
        userMessage.update(\.document, to: document)

        addAttachments(object.attachments, to: userMessage)
        await requestUpdate(view: currentMessageListView)

        // MARK: - 添加 Attachment 数据到持久化内容

        if case let .bool(value) = object.options[.ephemeral], !value {
            updateAttachments(object.attachments, for: userMessage)
        }
        saveIfNeeded(object)

        // MARK: - 预处理图片信息提取

        try checkCancellation()
        try await preprocessAttachments(
            &object,
            modelCapabilities.contains(.visual),
            currentMessageListView,
            userMessage,
        )
        saveIfNeeded(object)

        // MARK: - 开始提取搜索关键词 爬取网页

        try checkCancellation()
        try await preprocessSearchQueries(
            currentMessageListView,
            &object,
            requestLinkContentIndex: requestLinkContentIndex,
        )
        saveIfNeeded(object)

        // MARK: - 添加这次的附件

        if !object.attachments.isEmpty {
            await currentMessageListView.loading(with: String(localized: "Processing Attachments"))
            let attachmentMessages = await makeMessageFromAttachments(
                object.attachments,
                modelCapabilities: modelCapabilities,
            )
            requestMessages.append(contentsOf: attachmentMessages)
            saveIfNeeded(object)
        }

        // MARK: - 添加最新的系统提示

        await injectNewSystemCommand(&requestMessages, modelName, modelWillExecuteTools, object)

        // MARK: - 构建工具调用列表

        let servers = MCPService.shared.servers.value
        let shouldPrepareMCP = servers.filter(\.isEnabled).count > 0
        if shouldPrepareMCP {
            await currentMessageListView.loading(with: String(localized: "Preparing Model Context"))
            await MCPService.shared.prepareForConversation()
        }

        var tools: [ModelTool] = []
        if modelWillExecuteTools {
            await tools.append(contentsOf: ModelToolsManager.shared.getEnabledToolsIncludeMCP())
            if !modelWillGoSearchWeb {
                // remove this tool if not enabled
                tools = tools.filter { !($0 is MTWebSearchTool) }
            }
        }

        let toolsDefinitions = tools.isEmpty ? nil : tools.map(\.definition)

        await currentMessageListView.stopLoading()

        // MARK: - 删除超出上下文长度限制的消息

        try checkCancellation()
        if try removeOutOfContextContents(&requestMessages, toolsDefinitions, modelContextLength) {
            let hintMessage = appendNewMessage(role: .hint)
            hintMessage.update(\.document, to: String(localized: "Some messages have been removed to fit the model context length."))
            await requestUpdate(view: currentMessageListView)
        }

        // MARK: - 开始循环调用接口

        try checkCancellation()
        saveIfNeeded(object)

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
            saveIfNeeded(object)
        } while shouldContinue

        await requestUpdate(view: currentMessageListView)

        Logger.app.infoFile("inference done")

        // MARK: - 自动记忆提取和对话摘要

        let isEphemeral: Bool = {
            if case let .bool(value) = object.options[.ephemeral] { return value }
            return false
        }()

        if !isEphemeral {
            let recentMessages = Array(messages.suffix(6))
            let auxModel = models.auxiliary ?? models.chat
            let convId = id
            let allMessages = messages
            await MainActor.run {
                Task {
                    await MemoryExtractor.shared.extractIfNeeded(
                        from: recentMessages,
                        conversationId: convId.description,
                        using: auxModel
                    )
                    await ConversationSummarizer.shared.summarizeIfNeeded(
                        conversationId: convId,
                        messages: allMessages,
                        using: auxModel
                    )
                }
            }
        }

        // MARK: - 生成标题和图标

        try checkCancellation()
        if shouldAutoRename {
            await updateTitleAndIcon()
        }
    }
}

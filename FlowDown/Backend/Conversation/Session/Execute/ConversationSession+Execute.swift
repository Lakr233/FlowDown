//
//  ConversationSession+Execute.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/25/25.
//

import AlertController
import ChatClientKit
import RichEditor
import ScrubberKit
import Storage
import UIKit

extension ConversationSession {
    func doInfere(
        modelID: ModelManager.ModelIdentifier,
        currentMessageListView: MessageListView,
        inputObject: RichEditorView.Object,
        contextLimitMessageID: Message.ID? = nil,
        reuseUserMessageID: Message.ID? = nil,
        completion: @escaping () -> Void
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
                        DispatchQueue.main.async {
                            UIApplication.shared.endBackgroundTask(finalBackgroundTask)
                        }
                    }
                }

                await requestUpdate(view: currentMessageListView)
                await doInfereExecute(
                    modelID: modelID,
                    currentMessageListView: currentMessageListView,
                    inputObject: inputObject,
                    contextLimitMessageID: contextLimitMessageID,
                    reuseUserMessageID: reuseUserMessageID
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
        contextLimitMessageID: Message.ID?,
        reuseUserMessageID: Message.ID?
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
        buildInitialRequestMessages(
            &requestMessages,
            modelCapabilities,
            limitToMessageId: contextLimitMessageID
        )

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
                reuseUserMessageID
            )
            saveIfNeeded(object)
        } catch {
            logger.error("\(error.localizedDescription)")
            let errorMessage = appendNewMessage(role: .assistant)
            errorMessage.update(\.document, to: "*\(error.localizedDescription)*")
            await requestUpdate(view: currentMessageListView)
            await requestUpdate(view: currentMessageListView)
        }

        stopThinkingForAll()
        for message in messages {
            if message.document.hasSuffix(ModelManager.indicatorText) {
                var newDocument = message.document
                newDocument.removeLast(ModelManager.indicatorText.count)
                message.update(\.document, to: newDocument)
            }
            if message.reasoningContent.hasSuffix(ModelManager.indicatorText) {
                var newReasoningContent = message.reasoningContent
                newReasoningContent.removeLast(ModelManager.indicatorText.count)
                message.update(\.reasoningContent, to: newReasoningContent)
            }
        }

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
        _ reuseUserMessageID: Message.ID?
    ) async throws {
        try checkCancellation()
        await currentMessageListView.loading()

        // MARK: - 添加用户的消息到储存框架

        let document = object.text

        let userMessage: Message
        if let reuseUserMessageID,
           let existingUserMessage = message(for: reuseUserMessageID),
           existingUserMessage.role == .user
        {
            userMessage = existingUserMessage
            object.text = existingUserMessage.document
        } else {
            let newUserMessage = appendNewMessage(role: .user)
            newUserMessage.update(\.document, to: document)
            addAttachments(object.attachments, to: newUserMessage)
            userMessage = newUserMessage
        }

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
            userMessage
        )
        saveIfNeeded(object)

        // MARK: - 开始提取搜索关键词 爬取网页

        try checkCancellation()
        try await preprocessSearchQueries(
            currentMessageListView,
            &object,
            requestLinkContentIndex: requestLinkContentIndex
        )
        saveIfNeeded(object)

        // MARK: - 添加这次的附件

        if !object.attachments.isEmpty {
            let attachmentMessages = makeMessageFromAttachments(
                object.attachments,
                isModelSupportsVision: modelCapabilities.contains(.visual)
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

        // MARK: - 挪动系统提示词到最前面

        moveSystemMessagesToFront(&requestMessages)

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
                parentUserMessageId: userMessage.objectId,
                linkedContents: linkedContents,
                requestLinkContentIndex: requestLinkContentIndex
            )
            saveIfNeeded(object)
        } while shouldContinue

        await requestUpdate(view: currentMessageListView)

        Logger.app.infoFile("inference done")

        // MARK: - 生成标题和图标

        try checkCancellation()
        if shouldAutoRename {
            await updateTitleAndIcon()
        }
    }
}

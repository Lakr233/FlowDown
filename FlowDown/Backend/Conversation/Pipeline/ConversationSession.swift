//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Combine
import Foundation
import Storage

#if DEBUG
    extension ConversationSession {
        static var allowedInit: Conversation.ID?
    }
#endif

/// An object that coordinates the messages of a conversation.
final class ConversationSession: Identifiable {
    let id: Conversation.ID

    private(set) var messages: [Message] = []
    private(set) var attachments: [Message.ID: [Attachment]] = [:]
    private var thinkingDurationTimer: [Message.ID: Timer] = [:]

    private lazy var messagesSubject: CurrentValueSubject<
        ([Message], Bool),
        Never,
    > = .init((messages, false))
    var messagesDidChange: AnyPublisher<([Message], Bool), Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    private lazy var userDidSendMessageSubject = PassthroughSubject<Message, Never>()
    var userDidSendMessage: AnyPublisher<Message, Never> {
        userDidSendMessageSubject.eraseToAnyPublisher()
    }

    // MARK: - Activity Indicator

    /// The loading indicator's text: non-nil shows the indicator row (empty
    /// string = plain dots), nil hides it. Only written on the main queue.
    let activityText = CurrentValueSubject<String?, Never>(nil)

    // Main-queue-confined; every mutation funnels through DispatchQueue.main
    // so state transitions keep the order their call sites issued them in —
    // an unstructured Task per call would not guarantee that.
    private var activityRoundActive = false
    private var activityLastProgressAt: Date = .distantPast
    private var activitySilenceTimer: Timer?
    private static let activitySilenceInterval: TimeInterval = 2

    /// Shows the indicator with `text` until other activity replaces it.
    func showActivity(_ text: String = "") {
        DispatchQueue.main.async {
            self.activityRoundActive = true
            self.stopActivitySilenceTimer()
            if self.activityText.value != text { self.activityText.send(text) }
        }
    }

    /// Reports visible progress (a rendered token, an inserted row): hides the
    /// indicator, but re-shows it if the stream then stays silent for a while.
    func recordVisibleProgress() {
        DispatchQueue.main.async {
            self.activityRoundActive = true
            self.activityLastProgressAt = .now
            if self.activityText.value != nil { self.activityText.send(nil) }
            self.startActivitySilenceTimerIfNeeded()
        }
    }

    /// Hides the indicator without arming the silence fallback — for phases
    /// whose progress is visible elsewhere (tool status row, dialogs).
    func hideActivity() {
        DispatchQueue.main.async {
            self.stopActivitySilenceTimer()
            if self.activityText.value != nil { self.activityText.send(nil) }
        }
    }

    /// Ends the round: hides the indicator and disables the silence fallback.
    func endActivity() {
        DispatchQueue.main.async {
            self.activityRoundActive = false
            self.stopActivitySilenceTimer()
            if self.activityText.value != nil { self.activityText.send(nil) }
        }
    }

    private func startActivitySilenceTimerIfNeeded() {
        guard activitySilenceTimer == nil else { return }
        // One repeating probe instead of a timer per token: streaming can
        // deliver dozens of updates a second.
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }
            guard activityRoundActive else { return }
            guard Date.now.timeIntervalSince(activityLastProgressAt) >= Self.activitySilenceInterval else { return }
            stopActivitySilenceTimer()
            if activityText.value == nil { activityText.send("") }
        }
        RunLoop.main.add(timer, forMode: .common)
        activitySilenceTimer = timer
    }

    private func stopActivitySilenceTimer() {
        activitySilenceTimer?.invalidate()
        activitySilenceTimer = nil
    }

    var shouldAutoRename: Bool {
        get { ConversationManager.shared.conversation(identifier: id)?.shouldAutoRename ?? false }
        set {
            ConversationManager.shared.editConversation(identifier: id) { conv in
                conv.update(\.shouldAutoRename, to: newValue)
            }
        }
    }

    var currentTask: Task<Void, Never>?

    /// temporary storage for web search results
    /// it can be discarded after closing the app
    /// becase the [^1] ref will be replaced with the real url like [^1](https://example.com)
    var linkedContents: [Int: URL] = [:]

    deinit {
        currentTask?.cancel()
        currentTask = nil
        thinkingDurationTimer.values.forEach { $0.invalidate() }
        ConversationSessionManager.shared.markSessionCompleted(id)
    }

    init(id: Conversation.ID) {
        self.id = id
        #if DEBUG
            assert(Self.allowedInit == id)
            Self.allowedInit = nil
        #endif

        refreshContentsFromDatabase(sanitizeInterrupted: true)
        updateModels()
    }

    class Models {
        var chat: ModelManager.ModelIdentifier?
        var auxiliary: ModelManager.ModelIdentifier?
        var visualAuxiliary: ModelManager.ModelIdentifier?
    }

    var models: Models = .init() {
        didSet { Logger.model.infoFile("models updated \(models)") }
    }

    func prepareSystemPrompt() {
        let modelManager = ModelManager.shared
        var prompt = modelManager.defaultPrompt.createPrompt()
        let extra = modelManager.additionalPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extra.isEmpty {
            prompt += "\n" + extra
        }
        appendNewMessage(role: .system) {
            $0.update(\.document, to: prompt)
        }
    }

    /// Appends a new message to the conversation.
    @discardableResult
    func appendNewMessage(role: Message.Role, _ block: Storage.MessageMakeInitDataBlock? = nil) -> Message {
        let message = sdb.makeMessage(with: id) {
            if let block {
                block($0)
            }

            $0.update(\.role, to: role)
        }

        messages.append(message)
        if role == .user { userDidSendMessageSubject.send(message) }
        return message
    }

    private func updateAttachment(_ attachment: Attachment, using object: RichEditorView.Object.Attachment) {
//        attachment.objectId = object.id.uuidString
//        attachment.type = object.type.rawValue
//        attachment.name = object.name
//        attachment.previewImageData = object.previewImage
//        attachment.representedDocument = object.textRepresentation
//        attachment.storageSuffix = object.storageSuffix
//        attachment.imageRepresentation = object.imageRepresentation

        attachment.update(\.objectId, to: object.id.uuidString)
        attachment.update(\.type, to: object.type.rawValue)
        attachment.update(\.name, to: object.name)
        attachment.update(\.previewImageData, to: object.previewImage)
        attachment.update(\.representedDocument, to: object.textRepresentation)
        attachment.update(\.storageSuffix, to: object.storageSuffix)
        attachment.update(\.imageRepresentation, to: object.imageRepresentation)
    }

    func addAttachments(_ attachments: [RichEditorView.Object.Attachment], to message: Message) {
        let messageID = message.objectId
        let mapped = attachments.map { attachment in
            // 跳过插入，由后面的attachmentsUpdate 统一批量插入
            sdb.attachmentMake(with: messageID, skipSave: true) {
                self.updateAttachment($0, using: attachment)
            }
        }

        sdb.attachmentsUpdate(mapped)

        var current = self.attachments[messageID] ?? []
        current.append(contentsOf: mapped)
        self.attachments[message.objectId] = current
    }

    func updateAttachments(_ attachments: [RichEditorView.Object.Attachment], for message: Message) {
        let currentAttachments = self.attachments[message.objectId] ?? []
        for attachment in attachments {
            guard
                let current = currentAttachments.first(where: {
                    $0.objectId == attachment.id.uuidString
                })
            else {
                // If the attachment is not found, ignore it.
                continue
            }
            updateAttachment(current, using: attachment)
        }
        sdb.attachmentsUpdate(currentAttachments)
    }

    func notifyMessagesDidChange(scrolling: Bool = true) {
        messagesSubject.send((messages, scrolling))
    }

    /// - Parameter sanitizeInterrupted: Marks tool calls still recorded as
    ///   running as failed. Only the initial restore passes true: a running
    ///   state found there can only be a leftover from a terminated app.
    func refreshContentsFromDatabase(sanitizeInterrupted: Bool = false) {
        // Load historical messages from the database.
        assert(Thread.isMainThread, "refreshContentsFromDatabase must be called on main thread for UI coherence")
        messages.removeAll()
        attachments.removeAll()
        messages = sdb.listMessages(within: id)
        linkedContents.removeAll()
        var interruptedMessages: [Message] = []
        for message in messages {
            let id = message.objectId
            let attachments = sdb.attachment(for: id)
            if !attachments.isEmpty { self.attachments[id] = attachments }
            if !message.reasoningContent.isEmpty,
               message.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                message.update(\.document, to: String(localized: "Empty message."))
            }
            if sanitizeInterrupted, message.role == .toolHint, message.toolStatus.state == 0 {
                var status = message.toolStatus
                status.state = 2
                status.message = String(localized: "Tool call was interrupted.")
                message.update(\.toolStatus, to: status)
                interruptedMessages.append(message)
            }
        }
        if !interruptedMessages.isEmpty {
            sdb.messagePut(messages: interruptedMessages)
        }
        #if DEBUG
            assert(messages.allSatisfy { $0.conversationId == id })
        #endif
        notifyMessagesDidChange()
    }

    @inlinable
    func save() {
        sdb.messagePut(messages: messages)
    }

    @inlinable
    func message(for id: Message.ID) -> Message? {
        messages.first { $0.objectId == id }
    }

    @inlinable
    func attachments(for messageID: Message.ID) -> [Attachment] {
        attachments[messageID] ?? []
    }

    /// 删除这条消息
    func delete(messageIdentifier: Message.ID) {
        cancelCurrentTask { [self] in
            sdb.deleteSupplementMessage(nextTo: messageIdentifier)
            sdb.delete(messageIdentifier: messageIdentifier)
            refreshContentsFromDatabase()
        }
    }

    func discard(messageIdentifier: Message.ID) {
        sdb.deleteSupplementMessage(nextTo: messageIdentifier)
        sdb.delete(messageIdentifier: messageIdentifier)
        messages.removeAll { $0.objectId == messageIdentifier }
        attachments[messageIdentifier] = nil
        thinkingDurationTimer[messageIdentifier]?.invalidate()
        thinkingDurationTimer[messageIdentifier] = nil
    }

    /// 删除自这条消息以后的全部数据
    func deleteCurrentAndAfter(messageIdentifier: Message.ID, completion: @escaping () -> Void = {}) {
        cancelCurrentTask { [self] in
            sdb.deleteAfter(messageIdentifier: messageIdentifier)
            delete(messageIdentifier: messageIdentifier)
            Task {
                try? await Task.sleep(for: .milliseconds(100))
                await MainActor.run {
                    self.notifyMessagesDidChange()
                    completion()
                }
            }
        }
    }

    /// 更新单独的一条消息
    func update(messageIdentifier: Message.ID, content: String) {
        cancelCurrentTask { [self] in
            guard let message = messages.first(where: { $0.objectId == messageIdentifier }) else {
                return
            }
            message.update(\.document, to: content)
            // we have => representation.isThinking = messageContent.isEmpty .......
            if message.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                message.update(\.document, to: String(localized: "Empty message."))
            }
            sdb.messagePut(messages: [message])
            notifyMessagesDidChange()
        }
    }

    func update(messageIdentifier: Message.ID, reasoningContent: String) {
        guard let message = messages.first(where: { $0.objectId == messageIdentifier }) else {
            return
        }
        message.update(\.reasoningContent, to: reasoningContent)
        sdb.messagePut(messages: [message])
        notifyMessagesDidChange()
    }

    /// Starts a timer to calculate the thinking duration of the message.
    func startThinking(for id: Message.ID) {
        if thinkingDurationTimer[id] != nil { return }
        guard let message = messages.first(where: { $0.objectId == id }) else {
            assertionFailure()
            return
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            message.update(\.thinkingDuration, to: message.thinkingDuration + 1)
            notifyMessagesDidChange(scrolling: false)
        }
        RunLoop.main.add(timer, forMode: .common)
        thinkingDurationTimer[id] = timer
    }

    func stopThinkingForAll() {
        for value in thinkingDurationTimer.values {
            value.invalidate()
        }
        thinkingDurationTimer.removeAll()
    }

    func stopThinking(for id: Message.ID) {
        thinkingDurationTimer[id]?.invalidate()
        thinkingDurationTimer.removeValue(forKey: id)
    }

    func updateModels() {
        let conversation = ConversationManager.shared.conversation(identifier: id)

        // conversation model
        if let conversationModelId = conversation?.modelId, !conversationModelId.isEmpty {
            models.chat = conversationModelId
        } else if models.chat == nil || models.chat!.isEmpty {
            models.chat = .defaultModelForConversation
        }

        // task auxiliary model
        if ModelManager.ModelIdentifier.defaultModelForAuxiliaryTaskWillUseCurrentChatModel {
            // When "Use Chat Model" is enabled, always use the chat model
            models.auxiliary = models.chat ?? .defaultModelForAuxiliaryTask
        } else {
            // When "Use Chat Model" is disabled, use the stored auxiliary model
            // Only update if current value is nil or empty
            if models.auxiliary == nil || models.auxiliary!.isEmpty {
                models.auxiliary = .defaultModelForAuxiliaryTask
            }
        }

        // visual auxiliary model
        if models.visualAuxiliary == nil || models.visualAuxiliary!.isEmpty {
            models.visualAuxiliary = .defaultModelForAuxiliaryVisualTask
        }
    }

    func nearestUserMessage(beforeOrEqual messageIdentifier: Message.ID) -> Message? {
        guard let message = messages.first(where: { $0.objectId == messageIdentifier }) else {
            return nil
        }

        for idx in messages.indices.reversed() where messages[idx].creation <= message.creation {
            let message = messages[idx]
            // check if is user message
            if message.role == .user {
                return message
            }
        }
        return nil
    }

    func retry(byClearAfter messageIdentifier: Message.ID, currentMessageListView: MessageListView) {
        guard let nearestUserMessage = nearestUserMessage(beforeOrEqual: messageIdentifier) else {
            assertionFailure()
            return
        }

        let messageContent = nearestUserMessage.document
        let messageAttachments = attachments(for: nearestUserMessage.objectId)

        var editorObject = ConversationManager.shared.getRichEditorObject(identifier: id) ?? .init()
        editorObject.text = messageContent

        editorObject.attachments = messageAttachments.compactMap {
            attachment -> RichEditorView.Object.Attachment? in
            guard let type = RichEditorView
                .Object
                .Attachment
                .AttachmentType(rawValue: attachment.type)
            else { return nil }

            return RichEditorView.Object.Attachment(
                id: UUID(uuidString: attachment.id) ?? UUID(),
                type: type,
                name: attachment.name,
                previewImage: attachment.previewImageData,
                imageRepresentation: attachment.imageRepresentation,
                textRepresentation: attachment.representedDocument,
                storageSuffix: attachment.storageSuffix,
            )
        }

        guard let modelID = models.chat else {
            assertionFailure()
            return
        }

        deleteCurrentAndAfter(messageIdentifier: nearestUserMessage.objectId) {
            self.doInfere(
                modelID: modelID,
                currentMessageListView: currentMessageListView,
                inputObject: editorObject,
            ) {}
        }
    }
}

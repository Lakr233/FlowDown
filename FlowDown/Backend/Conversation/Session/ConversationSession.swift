//
//  Created by ktiays on 2025/2/12.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Combine
import Foundation
import RichEditor
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
        Never
    > = .init((messages, false))
    var messagesDidChange: AnyPublisher<([Message], Bool), Never> {
        messagesSubject.eraseToAnyPublisher()
    }

    private lazy var userDidSendMessageSubject = PassthroughSubject<Message, Never>()
    var userDidSendMessage: AnyPublisher<Message, Never> {
        userDidSendMessageSubject.eraseToAnyPublisher()
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

    // temporary storage for web search results
    // it can be discarded after closing the app
    // becase the [^1] ref will be replaced with the real url like [^1](https://example.com)
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

        refreshContentsFromDatabase()
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
            let newAttachment = sdb.attachmentMake(with: messageID, skipSave: true) {
                self.updateAttachment($0, using: attachment)
            }
            return newAttachment
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

    func refreshContentsFromDatabase() {
        // Load historical messages from the database.
        assert(Thread.isMainThread, "refreshContentsFromDatabase must be called on main thread for UI coherence")
        messages.removeAll()
        attachments.removeAll()
        messages = sdb.listMessages(within: id)
        linkedContents.removeAll()
        for message in messages {
            let id = message.objectId
            let attachments = sdb.attachment(for: id)
            if !attachments.isEmpty { self.attachments[id] = attachments }
            if !message.reasoningContent.isEmpty,
               message.document.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            {
                message.update(\.document, to: String(localized: "Empty message."))
            }
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

    // 删除这条消息
    func delete(messageIdentifier: Message.ID) {
        cancelCurrentTask { [self] in
            sdb.deleteSupplementMessage(nextTo: messageIdentifier)
            sdb.delete(messageIdentifier: messageIdentifier)
            refreshContentsFromDatabase()
        }
    }

    // 删除自这条消息以后的全部数据
    func deleteCurrentAndAfter(messageIdentifier: Message.ID, completion: @escaping () -> Void = {}) {
        cancelCurrentTask { [self] in
            sdb.deleteAfter(messageIdentifier: messageIdentifier)
            delete(messageIdentifier: messageIdentifier)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.notifyMessagesDidChange()
                completion()
            }
        }
    }

    // 更新单独的一条消息
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

    func nextAttemptIndex(forParent parentUserMessageId: Message.ID) -> Int {
        let attempts = messages.compactMap { message -> Int? in
            guard message.role == .assistant,
                  let metadata = message.replyMetadata,
                  metadata.parentUserMessageId == parentUserMessageId
            else {
                return nil
            }
            return metadata.attemptIndex
        }
        let maxAttempt = attempts.max() ?? 0
        return maxAttempt + 1
    }

    private func markAssistantMessageHistorical(
        _ assistantMessage: Message,
        parentUserMessage: Message
    ) {
        let parentId = parentUserMessage.objectId
        let attemptIndex: Int
        if let metadata = assistantMessage.replyMetadata {
            attemptIndex = metadata.attemptIndex
        } else {
            let attempts = messages.compactMap { message -> Int? in
                guard message.role == .assistant,
                      let metadata = message.replyMetadata,
                      metadata.parentUserMessageId == parentId
                else {
                    return nil
                }
                return metadata.attemptIndex
            }
            attemptIndex = max(attempts.max() ?? 0, 0) + 1
        }

        assistantMessage.replyMetadata = .init(
            parentUserMessageId: parentId,
            attemptIndex: attemptIndex,
            isHistorical: true
        )
        sdb.messagePut(messages: [assistantMessage])
        notifyMessagesDidChange(scrolling: false)
    }

    func retry(byClearAfter messageIdentifier: Message.ID, currentMessageListView: MessageListView) {
        guard let assistantMessage = message(for: messageIdentifier),
              assistantMessage.role == .assistant
        else {
            assertionFailure()
            return
        }

        guard let nearestUserMessage = nearestUserMessage(beforeOrEqual: messageIdentifier) else {
            assertionFailure()
            return
        }

        markAssistantMessageHistorical(assistantMessage, parentUserMessage: nearestUserMessage)

        let messageContent = nearestUserMessage.document
        let messageAttachments = attachments(for: nearestUserMessage.objectId)

        var editorObject = ConversationManager.shared.getRichEditorObject(identifier: id) ?? .init()
        editorObject.text = messageContent

        editorObject.attachments = messageAttachments.compactMap { attachment -> RichEditorView.Object.Attachment? in
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
                storageSuffix: attachment.storageSuffix
            )
        }

        guard let modelID = models.chat else {
            assertionFailure()
            return
        }

        doInfere(
            modelID: modelID,
            currentMessageListView: currentMessageListView,
            inputObject: editorObject,
            contextLimitMessageID: nearestUserMessage.objectId,
            reuseUserMessageID: nearestUserMessage.objectId
        ) {}
    }
}

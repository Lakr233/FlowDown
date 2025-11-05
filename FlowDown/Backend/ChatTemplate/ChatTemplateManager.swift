//
//  ChatTemplateManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import OrderedCollections
import Storage
import UIKit
import XMLCoder

class ChatTemplateManager {
    static let shared = ChatTemplateManager()

    @Published private(set) var templates: OrderedDictionary<ChatTemplate.ID, ChatTemplate> = [:]

    private let storage: Storage
    private var observers: [Any] = []
    private var cachedRecords: [ChatTemplate.ID: ChatTemplateRecord] = [:]
    private var maxSortIndex: Int = -1

    private init(storage: Storage = sdb) {
        self.storage = storage
        migrateLegacyTemplatesIfNeeded()
        reloadFromStorage()
        registerObservers()
    }

    deinit {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    func addTemplate(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        let sortIndex = nextSortIndex()
        let record = ChatTemplateRecord(
            objectId: template.id.uuidString,
            deviceId: Storage.deviceId,
            name: template.name,
            prompt: template.prompt,
            inheritApplicationPrompt: template.inheritApplicationPrompt,
            avatarData: template.avatar,
            sortIndex: sortIndex,
            creation: .now
        )

        do {
            try storage.insertChatTemplate(record)
            reloadFromStorage()
        } catch {
            Logger.model.errorFile("Failed to insert chat template: \(error.localizedDescription)")
        }
    }

    func template(for itemIdentifier: ChatTemplate.ID) -> ChatTemplate? {
        assert(Thread.isMainThread)
        return templates[itemIdentifier]
    }

    func update(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        guard let existing = cachedRecords[template.id] else {
            Logger.model.errorFile("Attempted to update unknown template \(template.id)")
            return
        }

        let record = ChatTemplateRecord(
            objectId: existing.objectId,
            deviceId: existing.deviceId,
            name: template.name,
            prompt: template.prompt,
            inheritApplicationPrompt: template.inheritApplicationPrompt,
            avatarData: template.avatar,
            sortIndex: existing.sortIndex,
            creation: existing.creation,
            modified: existing.modified,
            removed: false
        )

        do {
            try storage.updateChatTemplate(record)
            reloadFromStorage()
        } catch {
            Logger.model.errorFile("Failed to update chat template: \(error.localizedDescription)")
        }
    }

    func remove(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        remove(for: template.id)
    }

    func remove(for itemIdentifier: ChatTemplate.ID) {
        assert(Thread.isMainThread)
        do {
            try storage.markChatTemplateRemoved(id: itemIdentifier.uuidString)
            reloadFromStorage()
        } catch {
            Logger.model.errorFile("Failed to remove chat template: \(error.localizedDescription)")
        }
    }

    func reorderTemplates(_ orderedIDs: [ChatTemplate.ID]) {
        assert(Thread.isMainThread)
        guard !orderedIDs.isEmpty else { return }

        var orderMap: [String: Int] = [:]
        for (index, identifier) in orderedIDs.enumerated() {
            orderMap[identifier.uuidString] = index
        }

        do {
            try storage.updateChatTemplateOrders(orderMap)
            reloadFromStorage()
        } catch {
            Logger.model.errorFile("Failed to reorder chat templates: \(error.localizedDescription)")
        }
    }

    private func migrateLegacyTemplatesIfNeeded() {
        let defaults = UserDefaults.standard
        let legacyKey = "ChatTemplates"

        do {
            let existing = try storage.fetchAllChatTemplates(includeRemoved: true)
            if !existing.isEmpty {
                defaults.removeObject(forKey: legacyKey)
                return
            }
        } catch {
            Logger.model.errorFile("Failed to inspect existing templates: \(error.localizedDescription)")
            return
        }

        guard let data = defaults.data(forKey: legacyKey), !data.isEmpty else {
            return
        }

        do {
            let legacyTemplates = try PropertyListDecoder().decode(
                OrderedDictionary<ChatTemplate.ID, ChatTemplate>.self,
                from: data
            )

            guard !legacyTemplates.isEmpty else {
                defaults.removeObject(forKey: legacyKey)
                return
            }

            var records: [ChatTemplateRecord] = []
            let now = Date.now
            for (index, element) in legacyTemplates.enumerated() {
                let (identifier, template) = element
                let record = ChatTemplateRecord(
                    objectId: identifier.uuidString,
                    deviceId: Storage.deviceId,
                    name: template.name,
                    prompt: template.prompt,
                    inheritApplicationPrompt: template.inheritApplicationPrompt,
                    avatarData: template.avatar,
                    sortIndex: index,
                    creation: now
                )
                records.append(record)
            }

            if !records.isEmpty {
                try storage.insertChatTemplates(records)
            }

            defaults.removeObject(forKey: legacyKey)
            Logger.model.infoFile("Migrated legacy chat templates: \(records.count)")
        } catch {
            Logger.model.errorFile("Failed to migrate legacy templates: \(error.localizedDescription)")
        }
    }

    private func registerObservers() {
        let center = NotificationCenter.default

        let templateObserver = center.addObserver(
            forName: SyncEngine.ChatTemplateChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromStorage()
        }
        observers.append(templateObserver)

        let localDeletionObserver = center.addObserver(
            forName: SyncEngine.LocalDataDeleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadFromStorage()
        }
        observers.append(localDeletionObserver)

        let serverDeletionObserver = center.addObserver(
            forName: SyncEngine.ServerDataDeleted,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let success = notification.userInfo?["success"] as? Bool else {
                self?.reloadFromStorage()
                return
            }

            if success {
                self?.reloadFromStorage()
            }
        }
        observers.append(serverDeletionObserver)
    }

    private func reloadFromStorage() {
        assert(Thread.isMainThread)
        do {
            let records = try storage.fetchAllChatTemplates()
            var ordered: OrderedDictionary<ChatTemplate.ID, ChatTemplate> = [:]
            var newCache: [ChatTemplate.ID: ChatTemplateRecord] = [:]
            var newMax = -1

            for record in records {
                guard let template = template(from: record) else { continue }
                ordered[template.id] = template
                let copy = ChatTemplateRecord(
                    objectId: record.objectId,
                    deviceId: record.deviceId,
                    name: record.name,
                    prompt: record.prompt,
                    inheritApplicationPrompt: record.inheritApplicationPrompt,
                    avatarData: record.avatarData,
                    sortIndex: record.sortIndex,
                    creation: record.creation,
                    modified: record.modified,
                    removed: record.removed
                )
                newCache[template.id] = copy
                newMax = max(newMax, record.sortIndex)
            }

            cachedRecords = newCache
            maxSortIndex = newMax
            templates = ordered
        } catch {
            Logger.model.errorFile("Failed to reload chat templates: \(error.localizedDescription)")
        }
    }

    private func template(from record: ChatTemplateRecord) -> ChatTemplate? {
        guard let identifier = UUID(uuidString: record.objectId) else {
            return nil
        }

        return ChatTemplate(
            id: identifier,
            name: record.name,
            avatar: record.avatarData,
            prompt: record.prompt,
            inheritApplicationPrompt: record.inheritApplicationPrompt
        )
    }

    private func nextSortIndex() -> Int {
        maxSortIndex + 1
    }

    func createConversationFromTemplate(_ template: ChatTemplate) -> Conversation.ID {
        assert(Thread.isMainThread)
        let conversation = ConversationManager.shared.createNewConversation {
            $0.update(\.icon, to: template.avatar)
            $0.update(\.title, to: template.name)
            $0.update(\.shouldAutoRename, to: true)
        }

        let session = ConversationSessionManager.shared.session(for: conversation.id)
        defer {
            session.save()
            session.notifyMessagesDidChange()
        }

        if !template.prompt.isEmpty {
            if !template.inheritApplicationPrompt {
                let systemMessages = session.messages.filter { $0.role == .system }
                for message in systemMessages {
                    session.delete(messageIdentifier: message.objectId)
                }
            }
            session.appendNewMessage(role: .system) {
                $0.update(\.document, to: template.prompt)
            }
        }

        session.appendNewMessage(role: .hint) {
            $0.update(\.document, to: String(localized: "This conversation is based on the template: \(template.name)."))
        }

        return conversation.id
    }

    func createTemplateFromConversation(
        _ conversation: Conversation,
        model: ModelManager.ModelIdentifier,
        completion: @escaping (Result<ChatTemplate, Error>) -> Void
    ) {
        Task {
            do {
                let template = try await generateChatTemplate(from: conversation, using: model)
                await MainActor.run {
                    completion(.success(template))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    func rewriteTemplate(
        template: ChatTemplate,
        request: String,
        model: ModelManager.ModelIdentifier,
        completion: @escaping (Result<ChatTemplate, Error>) -> Void
    ) {
        Task {
            do {
                let template = try await rewriteTemplate(
                    template: template,
                    request: request,
                    model: model
                )
                await MainActor.run {
                    completion(.success(template))
                }
            } catch {
                await MainActor.run {
                    completion(.failure(error))
                }
            }
        }
    }

    private func rewriteTemplate(
        template: ChatTemplate,
        request: String,
        model: ModelManager.ModelIdentifier
    ) async throws -> ChatTemplate {
        let prompt = """
        You are a chat template expert. Please modify the following chat template according to the user's request. 

        IMPORTANT RULES:
        - Only change what the user specifically requests
        - If the user doesn't mention name or prompt, keep them unchanged
        - Respond ONLY with valid XML following the exact format provided
        - Do not include any text outside the XML structure
        - Use the user's preferred language for content

        Current template:
        <template>
        <name>\(template.name)</name>
        <prompt>\(template.prompt)</prompt>
        </template>

        User request: \(request)

        Please return the modified template in the same XML format, keeping unchanged fields exactly as they are.
        """

        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are a chat template editor. Modify only what the user requests, keeping everything else unchanged. Respond ONLY with valid XML in the exact format provided.")),
            .user(content: .text(prompt)),
        ]

        let response = try await ModelManager.shared.infer(with: model, input: messages)

        let parsedResponse = try parseTemplateResponse(response.content)
        return template.with {
            $0.name = parsedResponse.name
            $0.prompt = parsedResponse.prompt
        }
    }

    private func generateChatTemplate(from conversation: Conversation, using model: ModelManager.ModelIdentifier) async throws -> ChatTemplate {
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        // Get conversation messages for analysis
        let userMessages = session.messages.filter { $0.role == .user }
        let assistantMessages = session.messages.filter { $0.role == .assistant }

        guard !userMessages.isEmpty, !assistantMessages.isEmpty else {
            throw NSError(
                domain: "ChatTemplate",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Conversation does not have enough messages to create a template."),
                ]
            )
        }

        // Prepare conversation context
        let conversationContext = userMessages.prefix(3).map(\.document).joined(separator: "\n\n")
        let responseContext = assistantMessages.prefix(3).map(\.document).joined(separator: "\n\n")

        // Create XML structure for template generation
        let templateRequest = TemplateGenerationXML(
            task: String(localized: "Analyze the conversation and generate a reusable chat template. Extract the core purpose, create a concise name, suggest an appropriate emoji, and write a system prompt that captures the essence of the conversation pattern."),
            conversation_context: conversationContext,
            response_context: responseContext,
            output_format: TemplateGenerationXML.OutputFormat(
                name: "Short descriptive name for the template using concise language",
                emoji: "Single emoji representing the template purpose",
                prompt: "System prompt that captures the conversation pattern and purpose",
                inherit_app_prompt: true
            )
        )

        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted
        let xmlData = try encoder.encode(templateRequest, withRootKey: "template_generation")
        let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are a chat template generator. Analyze conversations and create reusable templates. Respond ONLY with valid XML following the exact format provided. Do not include any text outside the XML structure. Please ensure using user's preferred language inside conversation.")),
            .user(content: .text(xmlString)),
        ]

        let response = try await ModelManager.shared.infer(with: model, input: messages)

        return try parseTemplateResponse(response.content)
    }

    private func parseTemplateResponse(_ xmlString: String) throws -> ChatTemplate {
        let decoder = XMLDecoder()

        if let data = xmlString.data(using: .utf8),
           let templateResponse = try? decoder.decode(TemplateResponse.self, from: data)
        {
            let emojiData = templateResponse.emoji.textToImage(size: 64)?.pngData() ?? Data()

            return ChatTemplate(
                name: templateResponse.name.trimmingCharacters(in: .whitespacesAndNewlines),
                avatar: emojiData,
                prompt: templateResponse.prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                inheritApplicationPrompt: templateResponse.inherit_app_prompt
            )
        }

        return try parseTemplateUsingRegex(xmlString)
    }

    private func parseTemplateUsingRegex(_ xmlString: String) throws -> ChatTemplate {
        let namePattern = #"<name>(.*?)</name>"#
        let emojiPattern = #"<emoji>(.*?)</emoji>"#
        let promptPattern = #"<prompt>(.*?)</prompt>"#
        let inheritPattern = #"<inherit_app_prompt>(.*?)</inherit_app_prompt>"#

        guard let nameRegex = try? NSRegularExpression(pattern: namePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let emojiRegex = try? NSRegularExpression(pattern: emojiPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let promptRegex = try? NSRegularExpression(pattern: promptPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
              let inheritRegex = try? NSRegularExpression(pattern: inheritPattern, options: [.caseInsensitive, .dotMatchesLineSeparators])
        else {
            throw NSError(
                domain: "ChatTemplateGenerator",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: String(localized: "Failed to create regex patterns")]
            )
        }

        let range = NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)

        let name = if let nameMatch = nameRegex.firstMatch(in: xmlString, options: [], range: range),
                      let nameRange = Range(nameMatch.range(at: 1), in: xmlString)
        {
            String(xmlString[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw NSError(domain: "ChatTemplate", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Failed to extract required information from model response."),
            ])
        }

        let emoji = if let emojiMatch = emojiRegex.firstMatch(in: xmlString, options: [], range: range),
                       let emojiRange = Range(emojiMatch.range(at: 1), in: xmlString)
        {
            String(xmlString[emojiRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            "🤖"
        }

        let prompt = if let promptMatch = promptRegex.firstMatch(in: xmlString, options: [], range: range),
                        let promptRange = Range(promptMatch.range(at: 1), in: xmlString)
        {
            String(xmlString[promptRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            throw NSError(domain: "ChatTemplate", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Failed to extract required information from model response."),
            ])
        }

        let inheritAppPrompt: Bool
        if let inheritMatch = inheritRegex.firstMatch(in: xmlString, options: [], range: range),
           let inheritRange = Range(inheritMatch.range(at: 1), in: xmlString)
        {
            let inheritValue = String(xmlString[inheritRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            inheritAppPrompt = inheritValue == "true"
        } else {
            inheritAppPrompt = true
        }

        let emojiData = emoji.textToImage(size: 64)?.pngData() ?? Data()

        return ChatTemplate(
            name: name,
            avatar: emojiData,
            prompt: prompt,
            inheritApplicationPrompt: inheritAppPrompt
        )
    }
}

// MARK: - XML Models for Template Generation

private struct TemplateGenerationXML: Codable {
    let task: String
    let conversation_context: String
    let response_context: String
    let output_format: OutputFormat

    struct OutputFormat: Codable {
        let name: String
        let emoji: String
        let prompt: String
        let inherit_app_prompt: Bool
    }
}

private struct TemplateResponse: Codable {
    let name: String
    let emoji: String
    let prompt: String
    let inherit_app_prompt: Bool
}

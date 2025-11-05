//
//  ChatTemplateManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import Combine
import ChatClientKit
import Foundation
import OrderedCollections
import Storage
import UIKit
import XMLCoder

class ChatTemplateManager {
    static let shared = ChatTemplateManager()

    @Published private(set) var templates: OrderedDictionary<ChatTemplate.ID, ChatTemplate> = [:]
    private var templateRecords: OrderedDictionary<ChatTemplate.ID, ChatTemplateObject> = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {
        migrateLegacyTemplatesIfNeeded()
        reloadTemplatesFromStorage()

        NotificationCenter.default.publisher(for: SyncEngine.ChatTemplateChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadTemplatesFromStorage()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.LocalDataDeleted)
            .sink { [weak self] _ in
                self?.reloadTemplatesFromStorage()
            }
            .store(in: &cancellables)
    }

    func addTemplate(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        let object = ChatTemplateObject(deviceId: Storage.deviceId)
        object.objectId = template.id.uuidString
        object.name = template.name
        object.avatar = template.avatar
        object.prompt = template.prompt
        object.inheritApplicationPrompt = template.inheritApplicationPrompt
        object.sortIndex = nextSortIndex()
        let now = Date.now
        object.creation = now
        object.markModified(now)
        object.removed = false

        sdb.chatTemplateSave(object)
        reloadTemplatesFromStorage()
    }

    func template(for itemIdentifier: ChatTemplate.ID) -> ChatTemplate? {
        assert(Thread.isMainThread)
        return templates[itemIdentifier]
    }

    func update(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        assert(templates[template.id] != nil)
        guard let object = templateRecords[template.id] else {
            assertionFailure("Missing storage record for template \(template.id)")
            return
        }

        object.name = template.name
        object.avatar = template.avatar
        object.prompt = template.prompt
        object.inheritApplicationPrompt = template.inheritApplicationPrompt
        object.markModified()

        sdb.chatTemplateSave(object)
        reloadTemplatesFromStorage()
    }

    func remove(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        guard let object = templateRecords[template.id] else { return }
        sdb.chatTemplateMarkDelete(identifier: object.objectId)
        reloadTemplatesFromStorage()
    }

    func remove(for itemIdentifier: ChatTemplate.ID) {
        assert(Thread.isMainThread)
        guard let object = templateRecords[itemIdentifier] else { return }
        sdb.chatTemplateMarkDelete(identifier: object.objectId)
        reloadTemplatesFromStorage()
    }

    func reorderTemplates(_ orderedIDs: [ChatTemplate.ID]) {
        assert(Thread.isMainThread)
        guard !orderedIDs.isEmpty else { return }

        var updates: [ChatTemplateObject] = []
        for (index, id) in orderedIDs.enumerated() {
            guard let object = templateRecords[id] else { continue }
            if object.sortIndex != index {
                object.sortIndex = index
                object.markModified()
                updates.append(object)
            }
        }

        guard !updates.isEmpty else { return }
        sdb.chatTemplateSave(updates)
        reloadTemplatesFromStorage()
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

private extension ChatTemplateManager {
    func reloadTemplatesFromStorage() {
        assert(Thread.isMainThread)
        let objects = sdb.chatTemplateList()

        var records: OrderedDictionary<ChatTemplate.ID, ChatTemplateObject> = [:]
        var mapped: OrderedDictionary<ChatTemplate.ID, ChatTemplate> = [:]

        for object in objects {
            guard let uuid = UUID(uuidString: object.objectId) else {
                Logger.database.error("Invalid ChatTemplate objectId: \(object.objectId)")
                continue
            }

            records[uuid] = object
            mapped[uuid] = ChatTemplate(
                id: uuid,
                name: object.name,
                avatar: object.avatar,
                prompt: object.prompt,
                inheritApplicationPrompt: object.inheritApplicationPrompt
            )
        }

        templateRecords = records
        templates = mapped
    }

    func nextSortIndex() -> Int {
        templateRecords.values.map(\.sortIndex).max().map { $0 + 1 } ?? 0
    }

    func migrateLegacyTemplatesIfNeeded() {
        let existing = sdb.chatTemplateList(includeRemoved: true)
        guard existing.isEmpty else { return }

        guard let data = UserDefaults.standard.data(forKey: "ChatTemplates"),
              let decoded = try? PropertyListDecoder().decode(
                  OrderedDictionary<ChatTemplate.ID, ChatTemplate>.self,
                  from: data
              ),
              !decoded.isEmpty
        else {
            return
        }

        let now = Date.now
        var objects: [ChatTemplateObject] = []
        for (index, pair) in decoded.enumerated() {
            let (identifier, template) = pair
            let object = ChatTemplateObject(deviceId: Storage.deviceId)
            object.objectId = identifier.uuidString
            object.name = template.name
            object.avatar = template.avatar
            object.prompt = template.prompt
            object.inheritApplicationPrompt = template.inheritApplicationPrompt
            object.sortIndex = index
            object.creation = now
            object.markModified(now)
            object.removed = false
            objects.append(object)
        }

        sdb.chatTemplateSave(objects)
        UserDefaults.standard.removeObject(forKey: "ChatTemplates")
        Logger.database.info("Migrated legacy chat templates: \(objects.count, privacy: .public)")
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

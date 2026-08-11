//
//  ChatTemplateManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import ChatClientKit
import Combine
import ConfigurableKit
import Foundation
import OrderedCollections
import Storage
import UIKit

class ChatTemplateManager {
    static let shared = ChatTemplateManager()

    private let legacyStoreKey = "ChatTemplates"
    private let legacyMigrationFlagKey = "ChatTemplatesMigratedToStorage"
    private var cancellables = Set<AnyCancellable>()

    @Published private(set) var templates: OrderedDictionary<ChatTemplate.ID, ChatTemplate> = [:]

    private init() {
        reloadFromStorage()
        migrateLegacyTemplatesIfNeeded()
        observeSyncNotifications()
    }

    func addTemplate(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        let record = makeRecord(
            from: template,
            existing: nil,
            sortIndex: sdb.templateNextSortIndex(),
            shouldMarkModified: false,
        )
        sdb.templateSave(record: record)
        reloadFromStorage()
    }

    @discardableResult
    func importTemplate(from data: Data) throws -> ChatTemplate {
        let decoder = PropertyListDecoder()
        var template = try decoder.decode(ChatTemplate.self, from: data)

        // Always treat imports as a new object.
        // This prevents collisions with existing/soft-deleted records that can make imports appear to succeed but persist nothing.
        template.id = UUID()

        addTemplate(template)
        return template
    }

    func exportTemplateData(_ template: ChatTemplate) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        let data = try encoder.encode(template)

        // Validate round-trip decodability.
        _ = try PropertyListDecoder().decode(ChatTemplate.self, from: data)
        return data
    }

    func template(for itemIdentifier: ChatTemplate.ID) -> ChatTemplate? {
        assert(Thread.isMainThread)
        return templates[itemIdentifier]
    }

    func update(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        if let record = sdb.template(with: template.id.uuidString) {
            let updated = makeRecord(
                from: template,
                existing: record,
                sortIndex: record.sortIndex,
                shouldMarkModified: true,
            )
            sdb.templateSave(record: updated)
        } else {
            addTemplate(template)
            return
        }
        reloadFromStorage()
    }

    func remove(_ template: ChatTemplate) {
        assert(Thread.isMainThread)
        remove(for: template.id)
    }

    func remove(for itemIdentifier: ChatTemplate.ID) {
        assert(Thread.isMainThread)
        sdb.templateMarkDelete(identifier: itemIdentifier.uuidString)
        reloadFromStorage()
    }

    func reorderTemplates(_ orderedIDs: [ChatTemplate.ID]) {
        assert(Thread.isMainThread)
        guard !orderedIDs.isEmpty else { return }
        sdb.templateReorder(orderedIDs.map(\.uuidString))
        reloadFromStorage()
    }

    private func reloadFromStorage() {
        let records = sdb.templateList()
        let items = records.compactMap { makeTemplate(from: $0) }
        templates = OrderedDictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        Logger.model.infoFile("loaded \(templates.count) chat templates from storage")
    }

    private func makeTemplate(from record: ChatTemplateRecord) -> ChatTemplate {
        var template = ChatTemplate()
        let identifier = UUID(uuidString: record.objectId) ?? UUID()
        template = template.with {
            $0.id = identifier
            $0.name = record.name
            $0.avatar = record.avatar
            $0.prompt = record.prompt
            $0.inheritApplicationPrompt = record.inheritApplicationPrompt
        }
        if identifier.uuidString != record.objectId {
            let fixedRecord = makeRecord(
                from: template,
                existing: record,
                sortIndex: record.sortIndex,
                shouldMarkModified: true,
            )
            sdb.templateSave(record: fixedRecord)
        }
        return template
    }

    private func observeSyncNotifications() {
        NotificationCenter.default.publisher(for: SyncEngine.ChatTemplateChanged)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadFromStorage()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: SyncEngine.LocalDataDeleted)
            .debounce(for: .seconds(1), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.reloadFromStorage()
            }
            .store(in: &cancellables)
    }

    private func makeRecord(
        from template: ChatTemplate,
        existing: ChatTemplateRecord?,
        sortIndex: Double? = nil,
        creation: Date? = nil,
        shouldMarkModified: Bool = false,
    ) -> ChatTemplateRecord {
        let record = ChatTemplateRecord(
            deviceId: existing?.deviceId ?? Storage.deviceId,
            objectId: existing?.objectId ?? template.id.uuidString,
            name: template.name,
            avatar: template.avatar,
            prompt: template.prompt,
            inheritApplicationPrompt: template.inheritApplicationPrompt,
            sortIndex: sortIndex ?? existing?.sortIndex ?? sdb.templateNextSortIndex(),
            creation: creation ?? existing?.creation ?? Date.now,
        )
        if shouldMarkModified {
            record.markModified()
        }
        return record
    }

    private func migrateLegacyTemplatesIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: legacyMigrationFlagKey) == false else { return }
        guard templates.isEmpty else {
            defaults.set(true, forKey: legacyMigrationFlagKey)
            defaults.removeObject(forKey: legacyStoreKey)
            return
        }

        let data = defaults.data(forKey: legacyStoreKey) ?? Data()
        guard !data.isEmpty,
              let decoded = try? PropertyListDecoder().decode(
                  OrderedDictionary<ChatTemplate.ID, ChatTemplate>.self,
                  from: data,
              ),
              !decoded.isEmpty
        else {
            defaults.set(true, forKey: legacyMigrationFlagKey)
            defaults.removeObject(forKey: legacyStoreKey)
            return
        }

        let now = Date.now
        let records: [ChatTemplateRecord] = decoded.values.enumerated().map { index, template in
            makeRecord(
                from: template,
                existing: nil,
                sortIndex: Double(index),
                creation: now,
                shouldMarkModified: false,
            )
        }

        sdb.templateSave(records: records)
        defaults.set(true, forKey: legacyMigrationFlagKey)
        defaults.removeObject(forKey: legacyStoreKey)
        reloadFromStorage()
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
        completion: @escaping (Result<ChatTemplate, Error>) -> Void,
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
        completion: @escaping (Result<ChatTemplate, Error>) -> Void,
    ) {
        Task {
            do {
                let template = try await rewriteTemplate(
                    template: template,
                    request: request,
                    model: model,
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
        model: ModelManager.ModelIdentifier,
    ) async throws -> ChatTemplate {
        try Self.ensureToolCallCapability(of: model)

        let prompt = """
        Modify the following chat template according to the user's request.

        IMPORTANT RULES:
        - Only change what the user specifically requests
        - If the user doesn't mention name or prompt, keep them unchanged
        - Use the user's preferred language for content

        [current template name]
        \(template.name)

        [current template prompt]
        \(template.prompt)

        [user request]
        \(request)
        """

        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are a chat template editor. Modify only what the user requests, keeping everything else unchanged. You must call \(ChatTemplateToolCall.name) exactly once with the full resulting template. Do not respond with plain text.")),
            .user(content: .text(prompt)),
        ]

        let response = try await ModelManager.shared.infer(
            with: model,
            input: messages,
            tools: [ChatTemplateToolCall.definition],
            toolChoice: .function(name: ChatTemplateToolCall.name),
        )
        let arguments = try ChatTemplateToolCall.parse(response)
        return template.with {
            $0.name = arguments.trimmedName
            $0.prompt = arguments.trimmedPrompt
        }
    }

    private func generateChatTemplate(from conversation: Conversation, using model: ModelManager.ModelIdentifier) async throws -> ChatTemplate {
        try Self.ensureToolCallCapability(of: model)

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
                ],
            )
        }

        // Prepare conversation context
        let conversationContext = userMessages.prefix(3).map(\.document).joined(separator: "\n\n")
        let responseContext = assistantMessages.prefix(3).map(\.document).joined(separator: "\n\n")

        let prompt = """
        \(String(localized: "Analyze the conversation and generate a reusable chat template. Extract the core purpose, create a concise name, suggest an appropriate emoji, and write a system prompt that captures the essence of the conversation pattern."))

        [conversation context]
        \(conversationContext)

        [response context]
        \(responseContext)
        """

        let messages: [ChatRequestBody.Message] = [
            .system(content: .text("You are a chat template generator. Analyze conversations and create reusable templates. You must call \(ChatTemplateToolCall.name) exactly once with the generated template. Do not respond with plain text. Please ensure using user's preferred language inside conversation.")),
            .user(content: .text(prompt)),
        ]

        let response = try await ModelManager.shared.infer(
            with: model,
            input: messages,
            tools: [ChatTemplateToolCall.definition],
            toolChoice: .function(name: ChatTemplateToolCall.name),
        )
        let arguments = try ChatTemplateToolCall.parse(response)
        let emojiData = arguments.trimmedEmoji.textToImage(size: 64)?.pngData() ?? Data()

        return ChatTemplate(
            name: arguments.trimmedName,
            avatar: emojiData,
            prompt: arguments.trimmedPrompt,
            inheritApplicationPrompt: arguments.inherit_app_prompt ?? true,
        )
    }

    static func modelSupportsToolCalls(_ model: ModelManager.ModelIdentifier?) -> Bool {
        guard let model else { return false }
        return ModelManager.shared.modelCapabilities(identifier: model).contains(.tool)
    }

    private static func ensureToolCallCapability(of model: ModelManager.ModelIdentifier) throws {
        guard modelSupportsToolCalls(model) else {
            throw NSError(domain: "ChatTemplate", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "This model does not support tool call or no model is selected."),
            ])
        }
    }
}

// MARK: - Template Tool Call

private enum ChatTemplateToolCall {
    static let name = "save_chat_template"

    static var definition: ChatRequestBody.Tool {
        .function(
            name: name,
            description: "Save the resulting chat template.",
            parameters: [
                "type": "object",
                "properties": [
                    "name": [
                        "type": "string",
                        "description": "Short descriptive name for the template using concise language.",
                    ],
                    "emoji": [
                        "type": "string",
                        "description": "Single emoji representing the template purpose.",
                    ],
                    "prompt": [
                        "type": "string",
                        "description": "System prompt that captures the conversation pattern and purpose.",
                    ],
                    "inherit_app_prompt": [
                        "type": "boolean",
                        "description": "Whether the template should inherit the application-wide system prompt.",
                    ],
                ],
                "required": ["name", "emoji", "prompt", "inherit_app_prompt"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    struct Arguments: Decodable {
        let name: String
        let emoji: String?
        let prompt: String
        let inherit_app_prompt: Bool?

        var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
        var trimmedEmoji: String { (emoji ?? "🤖").trimmingCharacters(in: .whitespacesAndNewlines) }
        var trimmedPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    static func parse(_ response: ChatResponse) throws -> Arguments {
        guard let call = response.tools.first(where: { $0.name == name }),
              let data = call.args.data(using: .utf8),
              let arguments = try? JSONDecoder().decode(Arguments.self, from: data),
              !arguments.trimmedName.isEmpty,
              !arguments.trimmedPrompt.isEmpty
        else {
            throw NSError(domain: "ChatTemplate", code: -1, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Failed to extract required information from model response."),
            ])
        }
        return arguments
    }
}

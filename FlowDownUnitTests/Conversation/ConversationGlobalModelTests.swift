//
//  ConversationGlobalModelTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationGlobalModelTests {
    @Test
    @MainActor
    func `old conversation resolves to the global default without writing modelId`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let storedModel = "old-conversation-model-\(UUID().uuidString)"
        let conversation = sdb.conversationMake {
            $0.update(\.title, to: "Global Model Tests \(UUID().uuidString.prefix(8))")
            $0.update(\.modelId, to: storedModel)
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let before = try #require(sdb.conversationWith(identifier: conversation.id))

        let session = ConversationSessionManager.shared.session(for: conversation.id)
        session.models.chat = storedModel
        session.updateModels()

        #expect(session.models.chat == ModelManager.ModelIdentifier.defaultModelForConversation)
        let after = try #require(sdb.conversationWith(identifier: conversation.id))
        #expect(after.modelId == storedModel)
        #expect(after.modified == before.modified)
    }

    @Test
    func `tool registry has the page scraper and no web search`() {
        let names = ModelToolsManager.shared.tools.map(\.functionName)
        #expect(!names.contains("web_search"))
        #expect(names.contains("scrape_web_page"))
    }

    @Test
    @MainActor
    func `stored web search call still replays with valid arguments`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake {
            $0.update(\.title, to: "Global Model Tests \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        session.appendNewMessage(role: .user) { $0.update(\.document, to: "Question") }
        let row = session.appendNewMessage(role: .webSearch)
        session.encodeToolRequestAndAttachToToolMessage(
            ToolRequest(id: "old-search", name: "web_search", args: ""),
            message: row,
        )

        var replayed: [ChatRequestBody.Message] = []
        await session.buildInitialRequestMessages(&replayed, [])

        let calls = replayed.compactMap { message -> [ChatRequestBody.Message.ToolCall]? in
            if case let .assistant(_, toolCalls, _) = message { return toolCalls }
            return nil
        }.flatMap(\.self)
        let call = try #require(calls.first { $0.id == "old-search" })
        #expect(call.function.name == "web_search")
        #expect(call.function.arguments == "{}")
        #expect(replayed.contains {
            if case let .tool(_, toolCallID) = $0 { return toolCallID == "old-search" }
            return false
        })
    }

    @Test(arguments: [
        ("fireworks/models/deepseek-v4p1-flash-1017", "deepseek-v4p1-flash-1017"),
        ("plain-model", "plain-model"),
        ("vendor/ spaced-model ", "spaced-model"),
        ("vendor/model/", "vendor/model/"),
    ])
    func `model button shows the last path component`(name: String, expected: String) {
        #expect(ChatView.modelButtonTitle(for: name) == expected)
    }
}

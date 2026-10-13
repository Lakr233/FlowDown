//
//  DatabaseUpgradeTests.swift
//  StorageTests
//

import Foundation
@testable import Storage
import Testing
import WCDBSwift

struct DatabaseUpgradeTests {
    @Test
    func `legacy V1 database upgrades to the latest version without losing rows`() throws {
        try withTemporaryDirectory { directory in
            try seedLegacyDatabase(at: directory.appendingPathComponent("database.db"))

            let upgraded = try Storage.makeForTesting(databaseDir: directory)
            try expectLatestVersion(upgraded)
            try expectLegacyRows(in: upgraded)
            upgraded.db.close()

            // A second launch must find the upgraded schema and leave the data untouched.
            let reopened = try Storage.makeForTesting(databaseDir: directory)
            try expectLatestVersion(reopened)
            try expectLegacyRows(in: reopened)
            reopened.db.close()
        }
    }

    @Test
    func `fresh install creates the latest schema and survives a relaunch`() throws {
        try withTemporaryDirectory { directory in
            let storage = try Storage.makeForTesting(databaseDir: directory)
            try expectLatestVersion(storage)
            for table in [
                Conversation.tableName,
                Message.tableName,
                Attachment.tableName,
                CloudModel.tableName,
                Memory.tableName,
                ModelContextServer.tableName,
                ChatTemplateRecord.tableName,
                ConversationSummary.tableName,
                UploadQueue.tableName,
            ] {
                #expect(try storage.db.isTableExists(table), "missing table \(table)")
            }
            let conversation = storage.conversationMake { $0.update(\.title, to: "Fresh") }
            storage.db.close()

            let reopened = try Storage.makeForTesting(databaseDir: directory)
            try expectLatestVersion(reopened)
            #expect(reopened.conversationList().map(\.id) == [conversation.id])
            reopened.db.close()
        }
    }
}

private extension DatabaseUpgradeTests {
    func withTemporaryDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageUpgradeTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    func seedLegacyDatabase(at url: URL) throws {
        let legacy = Database(at: url.path)
        defer { legacy.close() }
        try MigrationV0ToV1().migrate(db: legacy)

        let conversation = ConversationV1()
        conversation.id = 1
        conversation.title = "Legacy Thread"
        conversation.isFavorite = true
        try legacy.insert(conversation, intoTable: ConversationV1.tableName)

        let question = MessageV1()
        question.id = 1
        question.conversationId = conversation.id
        question.role = .user
        question.document = "Hello"
        let answer = MessageV1()
        answer.id = 2
        answer.conversationId = conversation.id
        answer.role = .assistant
        answer.document = "World"
        try legacy.insert([question, answer], intoTable: MessageV1.tableName)

        try legacy.insert(MemoryV1(content: "Prefers metric units"), intoTable: MemoryV1.tableName)
        try legacy.insert(
            CloudModelV1(model_identifier: "legacy-model", endpoint: "https://example.com/v1/chat/completions"),
            intoTable: CloudModelV1.tableName,
        )
    }

    func expectLatestVersion(_ storage: Storage) throws {
        let version = try storage.db.getValue(from: StatementPragma().pragma(.userVersion))?.intValue
        #expect(version == DBVersion.allCases.last?.rawValue)
    }

    func expectLegacyRows(in storage: Storage) throws {
        let conversations = storage.conversationList()
        #expect(conversations.count == 1)
        guard let conversation = conversations.first else { return }
        #expect(conversation.title == "Legacy Thread")
        #expect(conversation.isFavorite)

        let messages = storage.listMessages(within: conversation.id)
        #expect(messages.map(\.document) == ["Hello", "World"])
        #expect(messages.map(\.role) == [.user, .assistant])

        #expect(try storage.getMemoriesWithLimit(10).map(\.content) == ["Prefers metric units"])
        #expect(storage.cloudModelList().map(\.model_identifier) == ["legacy-model"])
    }
}

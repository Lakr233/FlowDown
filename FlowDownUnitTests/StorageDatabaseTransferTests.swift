//
//  StorageDatabaseTransferTests.swift
//  FlowDownUnitTests
//

import Foundation
@testable import Storage
import Testing

@Suite(.serialized)
struct StorageDatabaseTransferTests {
    @Test
    func exportDatabase_includesModelContextServers() throws {
        try withTemporaryStorage { storage in
            _ = storage.modelContextServerMake {
                $0.update(\.name, to: "Example")
                $0.update(\.endpoint, to: "https://example.com/mcp")
            }

            let exportDirectory = try storage.exportDatabase().get()
            defer { try? FileManager.default.removeItem(at: exportDirectory) }

            let exported = try Storage.makeForTesting(name: "Exported", databaseDir: exportDirectory)
            #expect(exported.modelContextServerList().map(\.endpoint) == ["https://example.com/mcp"])
        }
    }

    /// Each case puts a creation tie on the 500-row page boundary. Paging by creation
    /// alone queued tied rows again on the next page (502 and 1000 rows, not 501).
    @Test(arguments: [(498, 3), (500, 1)])
    func reinitializeUploadQueue_creationTieAtPageBoundary_queuesEachRowOnce(
        firstCreationCount: Int,
        secondCreationCount: Int,
    ) throws {
        try withTemporaryStorage { storage in
            let conversation = storage.conversationMake { $0.update(\.title, to: "Shared Creation") }
            let firstCreation = Date(timeIntervalSince1970: 1_700_000_000)
            let creations = Array(repeating: firstCreation, count: firstCreationCount)
                + Array(repeating: firstCreation.addingTimeInterval(1), count: secondCreationCount)
            let messages: [Message] = creations.enumerated().map { index, creation in
                let message = storage.makeMessage(with: conversation.id, skipSave: true) {
                    $0.update(\.role, to: .user)
                    $0.update(\.document, to: "Message \(index)")
                }
                message.creation = creation
                return message
            }
            storage.messagePut(messages: messages)
            try #require(storage.listMessages(within: conversation.id).count == messages.count)

            try storage.reinitializeUploadQueue()

            // pendingUploadList(tables:) keeps one row per object, so read every queue row by id.
            let latest = storage.pendingUploadList(tables: [Message.tableName])
            let lastQueueID = try #require(latest.map(\.id).max())
            let queued = storage.pendingUploadList(queueIds: Array(0 ... lastQueueID))
                .filter { $0.tableName == Message.tableName }
            #expect(queued.count == messages.count)
            #expect(Set(queued.map(\.objectId)) == Set(messages.map(\.id)))
        }
    }
}

private extension StorageDatabaseTransferTests {
    func withTemporaryStorage(_ body: (Storage) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageDatabaseTransferTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let storage = try Storage.makeForTesting(databaseDir: directory)
        try body(storage)
    }
}

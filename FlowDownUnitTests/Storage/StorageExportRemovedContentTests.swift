//
//  StorageExportRemovedContentTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import SQLite3
@testable import Storage
import Testing

@Suite(.serialized)
struct StorageExportRemovedContentTests {
    @Test
    func exportDatabase_keepsActiveContentAndLeavesRemovedRowsEmpty() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try Storage.makeForTesting(databaseDir: directory)
        let fixture = makeFixture(in: storage)

        let before = try copy(of: directory)
        let exportDirectory = try storage.exportDatabase().get()
        let after = try copy(of: directory)
        defer {
            for url in [before, exportDirectory, after] {
                try? FileManager.default.removeItem(at: url)
            }
        }

        // the export only reads the database in use
        #expect(try tables(in: before) == tables(in: after))
        let blobLengths = "length(data), length(previewImageData), length(imageRepresentation)"
        #expect(try rows(
            "SELECT \(blobLengths) FROM Attachment WHERE objectId = '\(fixture.removedAttachment)'",
            in: after,
        ) == [[Fixture.blobSize, Fixture.blobSize, Fixture.blobSize].map(text)])

        // the removed rows are still there, with the same dates, so an import deletes them from iCloud
        for (table, objectId) in [
            ("Conversation", fixture.removedConversation),
            ("Message", fixture.removedMessage),
            ("Attachment", fixture.removedAttachment),
        ] {
            let query = "SELECT removed, creation, modified FROM \(table) WHERE objectId = '\(objectId)'"
            let exportedRows = try rows(query, in: exportDirectory)
            #expect(exportedRows.first?.first == text(1))
            #expect(try exportedRows == rows(query, in: after))
        }
        #expect(try rows(
            "SELECT \(blobLengths), length(representedDocument), messageId, type, name FROM Attachment WHERE objectId = '\(fixture.removedAttachment)'",
            in: exportDirectory,
        ) == [[text(0), text(0), text(0), text(0), Data(fixture.removedMessage.utf8), Data("image".utf8), Data("Removed".utf8)]])
        #expect(try rows(
            "SELECT length(document), length(reasoningContent), conversationId FROM Message WHERE objectId = '\(fixture.removedMessage)'",
            in: exportDirectory,
        ) == [[text(0), text(0), Data(fixture.removedConversation.utf8)]])

        // the exported file holds the three blobs in use and has no room for the three removed ones
        let exportedBytes = try rows(
            "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()",
            in: exportDirectory,
        ).first?.first.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
        #expect(try #require(exportedBytes) < Fixture.blobSize * 4)

        let exported = try Storage.makeForTesting(name: "Exported", databaseDir: exportDirectory)
        expectActiveContent(of: fixture, in: exported)
    }

    @Test
    @MainActor
    func importDatabase_ofAnExport_keepsActiveRowsAndQueuesRemovedRowsAsDeletions() async throws {
        let directory = try makeDirectory()
        let targetDirectory = try makeDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: targetDirectory)
        }
        let storage = try Storage.makeForTesting(databaseDir: directory)
        let fixture = makeFixture(in: storage)

        let archive = try storage.exportZipFile().get()
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        let target = try Storage.makeForTesting(name: "Target", databaseDir: targetDirectory)
        _ = target.conversationMake { $0.update(\.title, to: "Replaced") }
        let result = await withCheckedContinuation { continuation in
            target.importDatabase(from: archive) { continuation.resume(returning: $0) }
        }
        try result.get()

        let imported = try Storage.makeForTesting(name: "Imported", databaseDir: targetDirectory)
        expectActiveContent(of: fixture, in: imported)
        #expect(imported.conversationWith(identifier: fixture.removedConversation) == nil)
        #expect(imported.listMessages(within: fixture.removedConversation).isEmpty)
        #expect(imported.attachment(for: fixture.removedMessage).isEmpty)

        // a removed row goes to iCloud as a record deletion, which carries no content
        let queue = imported.pendingUploadList(
            tables: [Conversation.tableName, Message.tableName, Attachment.tableName],
        )
        let changes = Dictionary(uniqueKeysWithValues: queue.map { ($0.objectId, $0.changes) })
        #expect(changes == [
            fixture.activeConversation: .insert,
            fixture.activeMessage: .insert,
            fixture.activeAttachment: .insert,
            fixture.removedConversation: .delete,
            fixture.removedMessage: .delete,
            fixture.removedAttachment: .delete,
        ])
    }
}

private extension StorageExportRemovedContentTests {
    struct Fixture {
        static let blobSize = 512 * 1024
        var activeConversation = ""
        var activeMessage = ""
        var activeAttachment = ""
        var activeBlobs: [Data] = []
        var removedConversation = ""
        var removedMessage = ""
        var removedAttachment = ""
    }

    func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageExportRemovedContentTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// One conversation in use and one removed, each with a message and an image attachment.
    func makeFixture(in storage: Storage) -> Fixture {
        var fixture = Fixture()
        func blob() -> Data {
            Data((0 ..< Fixture.blobSize).map { _ in UInt8.random(in: .min ... .max) })
        }
        func populate(title: String, blobs: [Data]) -> (String, String, String) {
            let conversation = storage.conversationMake { $0.update(\.title, to: title) }
            let message = storage.makeMessage(with: conversation.id) {
                $0.update(\.role, to: .user)
                $0.update(\.document, to: "\(title) document")
                $0.update(\.reasoningContent, to: "\(title) reasoning")
            }
            let attachment = storage.attachmentMake(with: message.id) {
                $0.update(\.type, to: "image")
                $0.update(\.name, to: title)
                $0.update(\.data, to: blobs[0])
                $0.update(\.previewImageData, to: blobs[1])
                $0.update(\.imageRepresentation, to: blobs[2])
                $0.update(\.representedDocument, to: "\(title) text")
            }
            return (conversation.id, message.id, attachment.id)
        }

        fixture.activeBlobs = [blob(), blob(), blob()]
        (fixture.activeConversation, fixture.activeMessage, fixture.activeAttachment)
            = populate(title: "Active", blobs: fixture.activeBlobs)
        (fixture.removedConversation, fixture.removedMessage, fixture.removedAttachment)
            = populate(title: "Removed", blobs: [blob(), blob(), blob()])
        storage.conversationRemove(conversationWith: fixture.removedConversation)
        return fixture
    }

    func expectActiveContent(of fixture: Fixture, in storage: Storage) {
        #expect(storage.conversationList().map(\.id) == [fixture.activeConversation])
        #expect(storage.conversationList().map(\.title) == ["Active"])
        let messages = storage.listMessages(within: fixture.activeConversation)
        #expect(messages.map(\.id) == [fixture.activeMessage])
        #expect(messages.map(\.document) == ["Active document"])
        #expect(messages.map(\.reasoningContent) == ["Active reasoning"])
        let attachments = storage.attachment(for: fixture.activeMessage)
        #expect(attachments.map(\.id) == [fixture.activeAttachment])
        #expect(attachments.map(\.data) == [fixture.activeBlobs[0]])
        #expect(attachments.map(\.previewImageData) == [fixture.activeBlobs[1]])
        #expect(attachments.map(\.imageRepresentation) == [fixture.activeBlobs[2]])
        #expect(attachments.map(\.representedDocument) == ["Active text"])
    }

    func text(_ value: Int) -> Data {
        Data(String(value).utf8)
    }
}

// MARK: - Reading the database files

private extension StorageExportRemovedContentTests {
    struct QueryError: Error {
        let message: String
    }

    /// A copy of the database files. The tests read the copy with the system SQLite,
    /// so the handles Storage keeps on the original are never involved.
    func copy(of directory: URL) throws -> URL {
        let destination = try makeDirectory()
        for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            // SQLite rebuilds the shared memory file from the write-ahead log
            guard !file.lastPathComponent.hasSuffix("-shm") else { continue }
            try FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        return destination
    }

    func tables(in directory: URL) throws -> [String: [[Data]]] {
        var tables: [String: [[Data]]] = [:]
        for table in ["Conversation", "Message", "Attachment", "UploadQueue"] {
            tables[table] = try rows("SELECT * FROM \(table) ORDER BY rowid", in: directory)
        }
        return tables
    }

    /// Every column of every row, as the bytes SQLite stores or prints for it.
    func rows(_ sql: String, in directory: URL) throws -> [[Data]] {
        var database: OpaquePointer?
        let path = directory.appendingPathComponent("database.db").path
        guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(database)
            throw QueryError(message: "open \(path)")
        }
        defer { sqlite3_close(database) }

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw QueryError(message: String(cString: sqlite3_errmsg(database)))
        }
        defer { sqlite3_finalize(statement) }

        var result: [[Data]] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { return result }
            guard code == SQLITE_ROW else {
                throw QueryError(message: String(cString: sqlite3_errmsg(database)))
            }
            result.append((0 ..< sqlite3_column_count(statement)).map { column in
                guard let bytes = sqlite3_column_blob(statement, column) else { return Data() }
                return Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, column)))
            })
        }
    }
}

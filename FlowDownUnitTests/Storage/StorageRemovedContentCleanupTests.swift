//
//  StorageRemovedContentCleanupTests.swift
//  FlowDownUnitTests
//

import CloudKit
@testable import FlowDown
import Foundation
import MarkdownParser
import SQLite3
@testable import Storage
// Testing has an Attachment of its own
import class Storage.Attachment
import Testing

/// Covers the launch cleanup emptying removed messages and attachments, and the shrink of the database file.
@Suite(.serialized)
struct StorageRemovedContentCleanupTests {
    private static let tables = [Conversation.tableName, Message.tableName, Attachment.tableName]
    private static let zoneID = CKRecordZone.ID(zoneName: "FlowDownSync", ownerName: CKCurrentUserDefaultName)

    // MARK: - Emptying removed rows

    @Test
    func cleanup_emptiesRemovedMessagesAndAttachmentsAndKeepsWhatIdentifiesAndDatesThem() async throws {
        try await withCleanup { fixture, before, after, storage in
            for (table, columns) in [
                ("Message", "objectId, deviceId, conversationId, creation, role, thinkingDuration, isThinkingFold, removed, modified"),
                ("Attachment", "objectId, deviceId, messageId, type, name, storageSuffix, removed, creation, modified"),
            ] {
                let removed = "SELECT \(columns) FROM \(table) WHERE removed = 1 ORDER BY objectId"
                let rowsAfter = try rows(removed, in: after)
                #expect(rowsAfter.count == 2)
                #expect(try rowsAfter == rows(removed, in: before))
            }

            // the content was there before the cleanup and is gone after it
            let blobBytes = "SELECT length(data) + length(previewImageData) + length(imageRepresentation)"
                + " + length(representedDocument) FROM Attachment WHERE removed = 1"
            #expect(try rows(blobBytes, in: before).allSatisfy { $0 != [text(0)] })
            #expect(try rows(blobBytes, in: after) == [[text(0)], [text(0)]])
            let messageContent = "SELECT length(document), length(reasoningContent), metadata IS NULL, documentNodes"
                + " FROM Message WHERE removed = 1"
            let emptyMessage = [text(0), text(0), text(1), Data("[]".utf8)]
            #expect(try rows(messageContent, in: before).allSatisfy { $0 != emptyMessage })
            #expect(try rows(messageContent, in: after) == [emptyMessage, emptyMessage])

            // the emptied rows are still read as rows by the loader the sync engine uses
            let objects = try objects(in: storage)
            for identifier in [fixture.removedMessage, fixture.cascadedMessage] {
                let message = try #require(objects.messages[identifier])
                #expect(message.removed)
                #expect(message.document.isEmpty)
                #expect(message.reasoningContent.isEmpty)
                #expect(message.documentNodes.isEmpty)
                #expect(message.webSearchStatus.queries.isEmpty)
                #expect(message.toolStatus.message.isEmpty)
                #expect(message.metadata == nil)
            }
            for identifier in [fixture.removedAttachment, fixture.cascadedAttachment] {
                let attachment = try #require(objects.attachments[identifier])
                #expect(attachment.removed)
                #expect(attachment.data.isEmpty)
                #expect(attachment.previewImageData.isEmpty)
                #expect(attachment.imageRepresentation.isEmpty)
                #expect(attachment.representedDocument.isEmpty)
            }
        }
    }

    @Test
    func cleanup_leavesRowsInUseConversationsAndTheUploadQueueAsTheyWere() async throws {
        try await withCleanup { fixture, before, after, storage in
            for (query, count) in [
                ("SELECT * FROM Message WHERE removed = 0 ORDER BY objectId", 1),
                ("SELECT * FROM Attachment WHERE removed = 0 ORDER BY objectId", 1),
                ("SELECT * FROM Conversation ORDER BY objectId", 2),
                ("SELECT * FROM UploadQueue ORDER BY id", 13),
            ] {
                let rowsAfter = try rows(query, in: after)
                #expect(rowsAfter.count == count)
                #expect(try rowsAfter == rows(query, in: before))
            }
            expectContentInUse(of: fixture, in: storage)
        }
    }

    @Test
    func clearRemovedContent_writesNoRowASecondTime() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try Storage.makeForTesting(databaseDir: directory)
        _ = try makeFixture(in: storage)

        func clear() throws -> [Int] {
            let counts = Counts()
            try storage.runTransaction {
                let cleared = try storage.clearRemovedContent(
                    modifiedAfter: Date.now.addingTimeInterval(-60 * 60 * 24 * 30),
                    handle: $0,
                )
                counts.values = [cleared.messages, cleared.attachments]
            }
            return counts.values
        }
        #expect(try clear() == [2, 2])
        #expect(try clear() == [0, 0])
    }

    // MARK: - Sync

    /// Every queued row is handed to the sync engine as a save, which is the worst case: an emptied
    /// row sent as a save would replace the content another device still shows.
    @Test
    @MainActor
    func emptiedRemovedRows_goOutAsDeletionsAndNeverAsSaves() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = try Storage.makeForTesting(databaseDir: directory)
        let fixture = try makeFixture(in: storage)
        await storage.clearDeletedRecords().value
        #expect(try objects(in: storage).attachments[fixture.removedAttachment]?.data.isEmpty == true)

        let engine = SyncEngine(
            storage: storage,
            containerIdentifier: "iCloud.wiki.qaq.flowdown.tests.\(UUID().uuidString)",
            mode: .mock,
            automaticallySync: false,
        )
        let container = MockCloudContainer.createContainer(
            identifier: "iCloud.wiki.qaq.flowdown.tests.\(UUID().uuidString)",
        )
        let mock = MockSyncEngine(
            database: container.privateCloudDatabase,
            parentSyncEngine: engine,
            state: MockSyncEngineState(),
            delegate: engine,
        )
        let queue = storage.pendingUploadList(tables: Self.tables)
        #expect(queue.count == 8)
        let separator = SyncEngine.CKRecordSentQueueIdSeparator
        mock.state.add(pendingRecordZoneChanges: queue.map { entry in
            .saveRecord(CKRecord.ID(
                recordName: "\(entry.id)\(separator)\(entry.objectId)\(separator)\(Storage.deviceId)",
                zoneID: Self.zoneID,
            ))
        })
        let batch = try #require(await engine.nextRecordZoneChangeBatch(
            reason: .manual,
            options: CKSyncEngine.SendChangesOptions(),
            syncEngine: mock,
        ))

        let saved = batch.recordsToSave.compactMap { UploadQueue.parseCKRecordID($0.recordID.recordName)?.objectId }
        let deleted = batch.recordIDsToDelete.compactMap { UploadQueue.parseCKRecordID($0.recordName)?.objectId }
        #expect(Set(saved) == [fixture.conversation, fixture.message, fixture.attachment])
        #expect(saved.count == 3)
        #expect(Set(deleted) == [
            fixture.removedMessage, fixture.removedAttachment,
            fixture.removedConversation, fixture.cascadedMessage, fixture.cascadedAttachment,
        ])
        #expect(deleted.count == 5)

        // the saves carry the content of the rows in use
        for record in batch.recordsToSave {
            let payload = try #require(record.payloadData)
            switch UploadQueue.parseCKRecordID(record.recordID.recordName)?.tableName {
            case Attachment.tableName:
                let attachment = try Attachment.decodePayload(payload)
                #expect(!attachment.removed)
                #expect([attachment.data, attachment.previewImageData, attachment.imageRepresentation] == fixture.blobs)
            case Message.tableName:
                let message = try Message.decodePayload(payload)
                #expect(!message.removed)
                #expect(message.document == "In use document")
            default:
                #expect(try !Conversation.decodePayload(payload).removed)
            }
        }
    }

    // MARK: - Shrink

    @Test
    func shrink_makesTheFileSmallerAndKeepsTheContentInUse() async throws {
        try await withShrinkFixture { fixture, storage, defaults in
            var policy = Storage.ShrinkPolicy()
            policy.minimumReclaimableBytes = 256 * 1024
            let before = try storage.databaseUsage()
            #expect(before.reclaimableBytes >= Int64(Fixture.blobSize * 6))

            let result = storage.shrinkIfWorthwhile(policy: policy, defaults: defaults)
            let after = try storage.databaseUsage()
            #expect(result == .shrunk(bytesBefore: before.totalBytes, bytesAfter: after.totalBytes))
            #expect(after.totalBytes <= before.totalBytes - Int64(Fixture.blobSize * 6))
            #expect(after.freePageCount == 0)

            expectContentInUse(of: fixture, in: storage)
            #expect(try objects(in: storage).messages[fixture.removedMessage]?.removed == true)
            // the database takes writes again
            let written = storage.makeMessage(with: fixture.conversation) { $0.update(\.document, to: "After the shrink") }
            #expect(storage.listMessages(within: fixture.conversation).map(\.id) == [fixture.message, written.id])

            #expect(storage.shrinkIfWorthwhile(policy: policy, defaults: defaults) == .skipped(.tooSoon))
        }
    }

    @Test
    func shrink_isSkippedBelowTheThreshold() async throws {
        try await withShrinkFixture { fixture, storage, defaults in
            let before = try storage.databaseUsage()
            #expect(before.reclaimableBytes > 0)
            #expect(before.reclaimableBytes < Storage.ShrinkPolicy().minimumReclaimableBytes)

            #expect(storage.shrinkIfWorthwhile(defaults: defaults) == .skipped(.notEnoughReclaimable))
            #expect(try storage.databaseUsage() == before)
            #expect(defaults.object(forKey: Storage.nextShrinkDateKey) == nil)
            expectContentInUse(of: fixture, in: storage)
        }
    }

    /// WCDB's vacuum copies the rows to `database.db.factory/vacuum/temp` before it touches the
    /// database. This leaves a partial copy there, as a kill during that copy would, and opens the
    /// database again. A kill while the copy is moved into place is not covered.
    @Test
    func reopen_withALeftoverPartialVacuumCopy_readsAndWritesTheDatabase() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture: Fixture
        do {
            let storage = try Storage.makeForTesting(databaseDir: directory)
            fixture = try makeFixture(in: storage)
            await storage.clearDeletedRecords().value
        }

        let leftover = directory.appendingPathComponent("database.db.factory/vacuum/temp", isDirectory: true)
        try FileManager.default.createDirectory(at: leftover, withIntermediateDirectories: true)
        let database = try Data(contentsOf: directory.appendingPathComponent("database.db"))
        try database.prefix(database.count / 2).write(to: leftover.appendingPathComponent("database.db"))

        let storage = try Storage.makeForTesting(name: "Reopened", databaseDir: directory)
        expectContentInUse(of: fixture, in: storage)
        let written = storage.makeMessage(with: fixture.conversation) { $0.update(\.document, to: "After the reopen") }
        #expect(storage.listMessages(within: fixture.conversation).map(\.id) == [fixture.message, written.id])
    }
}

private final class Counts: @unchecked Sendable {
    var values: [Int] = []
}

// MARK: - Fixture

private extension StorageRemovedContentCleanupTests {
    /// - A conversation in use, with a message and attachment in use and a removed message and attachment.
    /// - A removed conversation whose message and attachment were removed with it.
    struct Fixture {
        /// Above the size from which a record payload is sent as an asset.
        static let blobSize = 128 * 1024

        var conversation = ""
        var message = ""
        var attachment = ""
        var blobs: [Data] = []

        var removedMessage = ""
        var removedAttachment = ""

        var removedConversation = ""
        var cascadedMessage = ""
        var cascadedAttachment = ""
    }

    func makeFixture(in storage: Storage) throws -> Fixture {
        func addMessage(to conversation: String, title: String) -> (message: String, attachment: String, blobs: [Data]) {
            let blobs = (0 ..< 3).map { _ in
                Data((0 ..< Fixture.blobSize).map { _ in UInt8.random(in: .min ... .max) })
            }
            var webSearchStatus = Message.WebSearchStatus()
            webSearchStatus.queries = ["query"]
            let message = storage.makeMessage(with: conversation) {
                $0.update(\.role, to: .user)
                $0.update(\.document, to: "\(title) document")
                $0.update(\.reasoningContent, to: "\(title) reasoning")
                $0.assign(\.documentNodes, to: MarkdownParser().parse("**\(title)** nodes").document)
                $0.assign(\.webSearchStatus, to: webSearchStatus)
                $0.assign(\.toolStatus, to: Message.ToolStatus(name: "tool", state: 1, message: "tool result"))
                $0.assign(\.metadata, to: Data("metadata".utf8))
            }
            let attachment = storage.attachmentMake(with: message.id) {
                $0.update(\.type, to: "image")
                $0.update(\.name, to: title)
                $0.update(\.data, to: blobs[0])
                $0.update(\.previewImageData, to: blobs[1])
                $0.update(\.imageRepresentation, to: blobs[2])
                $0.update(\.representedDocument, to: "\(title) text")
            }
            return (message.id, attachment.id, blobs)
        }

        var fixture = Fixture()
        fixture.conversation = storage.conversationMake { $0.update(\.title, to: "In use") }.id
        (fixture.message, fixture.attachment, fixture.blobs) = addMessage(to: fixture.conversation, title: "In use")
        (fixture.removedMessage, fixture.removedAttachment, _) = addMessage(to: fixture.conversation, title: "Removed")
        storage.delete(messageIdentifier: fixture.removedMessage)

        fixture.removedConversation = storage.conversationMake { $0.update(\.title, to: "Removed") }.id
        (fixture.cascadedMessage, fixture.cascadedAttachment, _)
            = addMessage(to: fixture.removedConversation, title: "Cascaded")
        storage.conversationRemove(conversationWith: fixture.removedConversation)

        // the storage API reports no failed write, so every row is counted here
        let objects = try objects(in: storage)
        #expect(objects.messages.count == 3)
        #expect(objects.messages.values.filter(\.removed).count == 2)
        #expect(objects.attachments.count == 3)
        #expect(objects.attachments.values.filter(\.removed).count == 2)
        return fixture
    }

    func expectContentInUse(of fixture: Fixture, in storage: Storage) {
        #expect(storage.conversationList().map(\.id) == [fixture.conversation])
        let messages = storage.listMessages(within: fixture.conversation).filter { $0.id == fixture.message }
        #expect(messages.map(\.document) == ["In use document"])
        #expect(messages.map(\.reasoningContent) == ["In use reasoning"])
        #expect(messages.map(\.metadata) == [Data("metadata".utf8)])
        let attachments = storage.attachment(for: fixture.message)
        #expect(attachments.map(\.id) == [fixture.attachment])
        #expect(attachments.map { [$0.data, $0.previewImageData, $0.imageRepresentation] } == [fixture.blobs])
        #expect(attachments.map(\.representedDocument) == ["In use text"])
    }

    /// The messages and attachments of a database, removed ones included. Each row has a queued
    /// upload, which is how removed rows are reached.
    func objects(in storage: Storage) throws -> (messages: [String: Message], attachments: [String: Attachment]) {
        let lastQueueID = try #require(storage.pendingUploadList(tables: Self.tables).map(\.id).max())
        var messages: [String: Message] = [:]
        var attachments: [String: Attachment] = [:]
        for entry in storage.pendingUploadList(queueIds: Array(0 ... lastQueueID), queryRealObject: true) {
            switch entry.realObject {
            case let message as Message: messages[message.objectId] = message
            case let attachment as Attachment: attachments[attachment.objectId] = attachment
            case is Conversation: break
            default: Issue.record("no row for the queued upload of \(entry.tableName) \(entry.objectId)")
            }
        }
        return (messages, attachments)
    }

    /// Runs the launch cleanup on the fixture and hands over copies of the database files from before
    /// and after it, and the database itself.
    func withCleanup(
        _ body: (Fixture, _ before: URL, _ after: URL, Storage) throws -> Void,
    ) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture: Fixture
        do {
            fixture = try makeFixture(in: Storage.makeForTesting(databaseDir: directory))
        }
        // Storage is released whenever the files are copied, so nothing writes to them meanwhile.
        let before = try copy(of: directory)
        defer { try? FileManager.default.removeItem(at: before) }
        do {
            let storage = try Storage.makeForTesting(databaseDir: directory)
            await storage.clearDeletedRecords().value
        }
        let after = try copy(of: directory)
        defer { try? FileManager.default.removeItem(at: after) }

        try body(fixture, before, after, Storage.makeForTesting(databaseDir: directory))
    }

    /// The fixture after the launch cleanup, with a place of its own for the date of the next shrink.
    func withShrinkFixture(_ body: (Fixture, Storage, UserDefaults) throws -> Void) async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let suite = "StorageRemovedContentCleanupTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let storage = try Storage.makeForTesting(databaseDir: directory)
        let fixture = try makeFixture(in: storage)
        await storage.clearDeletedRecords().value
        try body(fixture, storage, defaults)
    }

    func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageRemovedContentCleanupTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func text(_ value: Int) -> Data {
        Data(String(value).utf8)
    }
}

// MARK: - Reading the database files

private extension StorageRemovedContentCleanupTests {
    struct QueryError: Error {
        let message: String
    }

    /// A copy of the database files, which the tests read with the system SQLite.
    func copy(of directory: URL) throws -> URL {
        let destination = try makeDirectory()
        for name in ["database.db-wal", "database.db"] {
            let file = directory.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(name))
        }
        return destination
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

//
//  StorageExportRemovedContentTests.swift
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

/// Covers what a database export holds for removed rows, and what importing it sends to iCloud.
@Suite(.serialized)
struct StorageExportRemovedContentTests {
    private static let tables = [Conversation.tableName, Message.tableName, Attachment.tableName]
    private static let zoneID = CKRecordZone.ID(zoneName: "FlowDownSync", ownerName: CKCurrentUserDefaultName)
    private static let recordType: CKRecord.RecordType = "SyncObject"

    // MARK: - Export

    @Test
    func exportDatabase_copiesRowsInUseWholeAndEmptiesRemovedMessagesAndAttachments() throws {
        try withExport { fixture, source, live, exported in
            // every column of every row in use is the same in the export
            for (table, count) in [("Conversation", 1), ("Message", 2), ("Attachment", 2)] {
                let inUse = "SELECT * FROM \(table) WHERE removed = 0 ORDER BY objectId"
                let exportedRows = try rows(inUse, in: exported)
                #expect(exportedRows.count == count)
                let different = try differences(inUse, between: exported, and: live)
                #expect(different == [])
            }

            // removed conversations are exported whole
            let removedConversations = "SELECT * FROM Conversation WHERE removed = 1 ORDER BY objectId"
            #expect(try rows(removedConversations, in: exported).count == 2)
            let differentConversations = try differences(removedConversations, between: exported, and: live)
            #expect(differentConversations == [])

            // removed messages and attachments keep the columns that identify and date them
            for (table, columns) in [
                ("Message", "objectId, deviceId, conversationId, creation, role, thinkingDuration, isThinkingFold, removed, modified"),
                ("Attachment", "objectId, deviceId, messageId, type, name, storageSuffix, removed, creation, modified"),
            ] {
                let removed = "SELECT \(columns) FROM \(table) WHERE removed = 1 ORDER BY objectId"
                let exportedRows = try rows(removed, in: exported)
                #expect(exportedRows.count == 2)
                #expect(try exportedRows == rows(removed, in: live))
            }

            // and none of their content
            let blobBytes = "length(data) + length(previewImageData) + length(imageRepresentation)"
            let removedAttachments = "FROM Attachment WHERE removed = 1"
            #expect(try rows("SELECT \(blobBytes) \(removedAttachments)", in: live)
                == [[text(Fixture.blobSize * 3)], [text(Fixture.blobSize * 3)]])
            #expect(try rows("SELECT \(blobBytes) + length(representedDocument) \(removedAttachments)", in: exported)
                == [[text(0)], [text(0)]])
            #expect(try rows(
                "SELECT length(document), length(reasoningContent), metadata IS NULL FROM Message WHERE removed = 1",
                in: exported,
            ) == [[text(0), text(0), text(1)], [text(0), text(0), text(1)]])

            // the exported file holds the six blobs in use and has no room for the six removed ones
            let exportedBytes = try rows(
                "SELECT page_count * page_size FROM pragma_page_count(), pragma_page_size()",
                in: exported,
            ).first?.first.flatMap { Int(String(decoding: $0, as: UTF8.self)) }
            #expect(try #require(exportedBytes) < Fixture.blobSize * 10)

            let exportedStorage = try Storage.makeForTesting(name: "Exported", databaseDir: exported)
            expectContentInUse(of: fixture, in: exportedStorage)
            try exportedStorage.reinitializeUploadQueue()
            let exportedObjects = try objects(in: exportedStorage)
            for identifier in [fixture.removedMessage, fixture.cascadedMessage] {
                let sourceMessage = try #require(source.messages[identifier])
                #expect(sourceMessage.removed)
                #expect(!sourceMessage.document.isEmpty)
                #expect(!sourceMessage.reasoningContent.isEmpty)
                #expect(!sourceMessage.documentNodes.isEmpty)
                #expect(sourceMessage.webSearchStatus.queries == ["query"])
                #expect(sourceMessage.toolStatus.message == "tool result")
                #expect(sourceMessage.metadata == Data("metadata".utf8))

                let message = try #require(exportedObjects.messages[identifier])
                #expect(message.removed)
                #expect(message.document.isEmpty)
                #expect(message.reasoningContent.isEmpty)
                #expect(message.documentNodes.isEmpty)
                var emptySearch = Message.WebSearchStatus()
                emptySearch.id = message.webSearchStatus.id
                #expect(message.webSearchStatus == emptySearch)
                var emptyTool = Message.ToolStatus()
                emptyTool.id = message.toolStatus.id
                #expect(message.toolStatus == emptyTool)
                #expect(message.metadata == nil)
            }
            for identifier in [fixture.removedAttachment, fixture.cascadedAttachment] {
                let attachment = try #require(exportedObjects.attachments[identifier])
                #expect(attachment.removed)
                #expect(attachment.data.isEmpty)
                #expect(attachment.previewImageData.isEmpty)
                #expect(attachment.imageRepresentation.isEmpty)
                #expect(attachment.representedDocument.isEmpty)
            }
        }
    }

    /// A message and attachment that are not marked removed are uploaded as saves after an import,
    /// so the export has to keep their content even when their conversation is removed.
    @Test
    func exportDatabase_keepsContentOfRowsInUseUnderARemovedConversation() throws {
        try withExport { fixture, _, live, exported in
            #expect(try rows(
                "SELECT removed FROM Conversation WHERE objectId = '\(fixture.orphanConversation)'",
                in: exported,
            ) == [[text(1)]])
            for (table, identifier) in [("Message", fixture.orphanMessage), ("Attachment", fixture.orphanAttachment)] {
                let row = "SELECT * FROM \(table) WHERE objectId = '\(identifier)'"
                let exportedRows = try rows(row, in: exported)
                #expect(exportedRows.count == 1)
                let different = try differences(row, between: exported, and: live)
                #expect(different == [])
                #expect(try rows("SELECT removed FROM \(table) WHERE objectId = '\(identifier)'", in: exported) == [[text(0)]])
            }
            #expect(try rows(
                "SELECT data, previewImageData, imageRepresentation FROM Attachment WHERE objectId = '\(fixture.orphanAttachment)'",
                in: exported,
            ) == [fixture.orphanBlobs])
        }
    }

    // MARK: - Import

    @Test
    @MainActor
    func importDatabase_ofAnExport_keepsRowsInUseAndQueuesRemovedRowsAsDeletions() async throws {
        let imported = try await ImportedExport(self)
        defer { imported.tearDown() }
        let fixture = imported.fixture

        expectContentInUse(of: fixture, in: imported.storage)
        #expect(imported.storage.conversationWith(identifier: fixture.removedConversation) == nil)
        #expect(imported.storage.listMessages(within: fixture.removedConversation).isEmpty)
        #expect(imported.storage.attachment(for: fixture.removedMessage).isEmpty)
        #expect(imported.storage.attachment(for: fixture.cascadedMessage).isEmpty)

        // the rows in use under the removed conversation still have their content
        #expect(imported.storage.conversationWith(identifier: fixture.orphanConversation) == nil)
        #expect(imported.storage.listMessages(within: fixture.orphanConversation).map(\.document) == ["Orphan document"])
        let orphanAttachments = imported.storage.attachment(for: fixture.orphanMessage)
        #expect(orphanAttachments.map(\.id) == [fixture.orphanAttachment])
        #expect(orphanAttachments.map { [$0.data, $0.previewImageData, $0.imageRepresentation] } == [fixture.orphanBlobs])

        // a removed row goes to iCloud as a record deletion, which carries no content
        let queue = imported.storage.pendingUploadList(tables: Self.tables)
        let changes = Dictionary(uniqueKeysWithValues: queue.map { ($0.objectId, $0.changes) })
        #expect(changes == fixture.expectedChanges)
    }

    // MARK: - Sync after an import

    @Test
    @MainActor
    func importedExport_sendsRemovedRowsAsDeletionsAndRowsInUseWithTheirContent() async throws {
        let imported = try await ImportedExport(self)
        defer { imported.tearDown() }
        let fixture = imported.fixture
        let engine = makeEngine(storage: imported.storage)
        let queue = imported.storage.pendingUploadList(tables: Self.tables)
        #expect(queue.count == fixture.expectedChanges.count)

        let saved = Set(fixture.expectedChanges.filter { $0.value == .insert }.keys)
        let deleted = Set(fixture.expectedChanges.filter { $0.value == .delete }.keys)

        // First the changes as scheduleUploadIfNeeded adds them, then every queued row as a save:
        // a removed row is turned into a deletion either way.
        for deletionsAsSaves in [false, true] {
            let mock = makeMock(engine: engine)
            mock.state.add(pendingRecordZoneChanges: pendingChanges(for: queue, deletionsAsSaves: deletionsAsSaves))
            let batch = try #require(await engine.nextRecordZoneChangeBatch(
                reason: .manual,
                options: CKSyncEngine.SendChangesOptions(),
                syncEngine: mock,
            ))

            #expect(Set(batch.recordsToSave.compactMap(recordObjectId)) == saved)
            #expect(batch.recordsToSave.count == saved.count)
            #expect(Set(batch.recordIDsToDelete.compactMap(objectId)) == deleted)
            #expect(batch.recordIDsToDelete.count == deleted.count)

            // the saved records carry the content of the rows in use
            var savedBlobs: [String: [Data]] = [:]
            var savedDocuments: [String: String] = [:]
            for record in batch.recordsToSave {
                let payload = try #require(record.payloadData)
                switch UploadQueue.parseCKRecordID(record.recordID.recordName)?.tableName {
                case Attachment.tableName:
                    let attachment = try Attachment.decodePayload(payload)
                    #expect(!attachment.removed)
                    savedBlobs[attachment.objectId] = [
                        attachment.data, attachment.previewImageData, attachment.imageRepresentation,
                    ]
                case Message.tableName:
                    let message = try Message.decodePayload(payload)
                    #expect(!message.removed)
                    savedDocuments[message.objectId] = message.document
                default:
                    #expect(try !Conversation.decodePayload(payload).removed)
                }
            }
            #expect(savedBlobs == [
                fixture.attachment: fixture.blobs,
                fixture.orphanAttachment: fixture.orphanBlobs,
            ])
            #expect(savedDocuments == [
                fixture.message: "In use document",
                fixture.orphanMessage: "Orphan document",
            ])
        }
    }

    /// The server can still hold the record of a row that is removed and empty after the import.
    @Test
    @MainActor
    func importedExport_fetchedRecordOfARemovedRow_neverSavesTheEmptyRow() async throws {
        let imported = try await ImportedExport(self)
        defer { imported.tearDown() }
        let fixture = imported.fixture
        let storage = imported.storage
        let engine = makeEngine(storage: storage)
        let local = try #require(try objects(in: storage).attachments[fixture.removedAttachment])
        #expect(local.removed)
        #expect(local.imageRepresentation.isEmpty)

        func serverRecord(modifiedMilliseconds: Int64) -> CKRecord {
            let record = CKRecord(
                recordType: Self.recordType,
                recordID: CKRecord.ID(
                    recordName: "\(fixture.removedAttachment)\(UploadQueue.CKRecordIDSeparator)\(Attachment.tableName)",
                    zoneID: Self.zoneID,
                ),
            )
            record.encryptedValues["payload"] = fixture.removedAttachmentPayload
            record.lastModifiedMilliseconds = modifiedMilliseconds
            return record
        }
        /// What would be sent if every queued row were scheduled as a save.
        func nextBatch() async throws -> CKSyncEngine.RecordZoneChangeBatch {
            let mock = makeMock(engine: engine)
            // by queue id, which also lists the uploads an earlier batch has taken
            let queue = storage.pendingUploadList(queueIds: Array(0 ... 1000))
            mock.state.add(pendingRecordZoneChanges: pendingChanges(for: queue, deletionsAsSaves: true))
            return try #require(await engine.nextRecordZoneChangeBatch(
                reason: .manual,
                options: CKSyncEngine.SendChangesOptions(),
                syncEngine: mock,
            ))
        }

        // an older server copy: the row stays removed and goes out as a deletion
        try storage.handleRemoteUpsert(modifications: [
            serverRecord(modifiedMilliseconds: local.modified.millisecondsSince1970 - 1000),
        ])
        #expect(storage.attachment(for: fixture.removedMessage).isEmpty)
        #expect(storage.pendingUploadList(tables: [Attachment.tableName])
            .filter { $0.objectId == fixture.removedAttachment }.map(\.changes) == [.delete])
        var batch = try await nextBatch()
        #expect(!batch.recordsToSave.compactMap(recordObjectId).contains(fixture.removedAttachment))
        #expect(batch.recordIDsToDelete.compactMap(objectId).contains(fixture.removedAttachment))

        // a newer server copy replaces the whole row, so the row has the server's content again
        try storage.handleRemoteUpsert(modifications: [
            serverRecord(modifiedMilliseconds: local.modified.millisecondsSince1970 + 1000),
        ])
        let restored = storage.attachment(for: fixture.removedMessage)
        #expect(restored.map(\.id) == [fixture.removedAttachment])
        #expect(restored.map { [$0.data, $0.previewImageData, $0.imageRepresentation] } == [fixture.removedBlobs])
        batch = try await nextBatch()
        #expect(!batch.recordsToSave.compactMap(recordObjectId).contains(fixture.removedAttachment))
    }
}

// MARK: - Fixture

private extension StorageExportRemovedContentTests {
    /// - A conversation in use, with a message and attachment in use and a removed message and attachment.
    /// - A removed conversation whose message and attachment were removed with it.
    /// - A removed conversation whose message and attachment are not marked removed.
    struct Fixture {
        /// Above the size from which a record payload is sent as an asset.
        static let blobSize = 128 * 1024

        var conversation = ""
        var message = ""
        var attachment = ""
        var blobs: [Data] = []

        var removedMessage = ""
        var removedAttachment = ""
        var removedBlobs: [Data] = []
        /// The record payload of the removed attachment from before it was removed.
        var removedAttachmentPayload = Data()

        var removedConversation = ""
        var cascadedMessage = ""
        var cascadedAttachment = ""

        var orphanConversation = ""
        var orphanMessage = ""
        var orphanAttachment = ""
        var orphanBlobs: [Data] = []

        /// The upload each row is queued for once the export is imported.
        var expectedChanges: [String: UploadQueue.Changes] {
            [
                conversation: .insert,
                message: .insert,
                attachment: .insert,
                removedMessage: .delete,
                removedAttachment: .delete,
                removedConversation: .delete,
                cascadedMessage: .delete,
                cascadedAttachment: .delete,
                orphanConversation: .delete,
                orphanMessage: .insert,
                orphanAttachment: .insert,
            ]
        }
    }

    func makeFixture(in storage: Storage) throws -> Fixture {
        func addMessage(to conversation: String, title: String) -> (message: String, attachment: Attachment, blobs: [Data]) {
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
            return (message.id, attachment, blobs)
        }

        var fixture = Fixture()

        fixture.conversation = storage.conversationMake { $0.update(\.title, to: "In use") }.id
        let inUse = addMessage(to: fixture.conversation, title: "In use")
        (fixture.message, fixture.attachment, fixture.blobs) = (inUse.message, inUse.attachment.id, inUse.blobs)
        let removed = addMessage(to: fixture.conversation, title: "Removed")
        (fixture.removedMessage, fixture.removedAttachment, fixture.removedBlobs)
            = (removed.message, removed.attachment.id, removed.blobs)
        fixture.removedAttachmentPayload = try removed.attachment.encodePayload()
        storage.delete(messageIdentifier: fixture.removedMessage)

        fixture.removedConversation = storage.conversationMake { $0.update(\.title, to: "Removed") }.id
        let cascaded = addMessage(to: fixture.removedConversation, title: "Cascaded")
        (fixture.cascadedMessage, fixture.cascadedAttachment) = (cascaded.message, cascaded.attachment.id)
        storage.conversationRemove(conversationWith: fixture.removedConversation)

        fixture.orphanConversation = storage.conversationMake { $0.update(\.title, to: "Removed alone") }.id
        storage.conversationRemove(conversationWith: fixture.orphanConversation)
        let orphan = addMessage(to: fixture.orphanConversation, title: "Orphan")
        (fixture.orphanMessage, fixture.orphanAttachment, fixture.orphanBlobs)
            = (orphan.message, orphan.attachment.id, orphan.blobs)

        return fixture
    }

    func expectContentInUse(of fixture: Fixture, in storage: Storage) {
        #expect(storage.conversationList().map(\.id) == [fixture.conversation])
        #expect(storage.conversationList().map(\.title) == ["In use"])
        let messages = storage.listMessages(within: fixture.conversation)
        #expect(messages.map(\.id) == [fixture.message])
        #expect(messages.map(\.document) == ["In use document"])
        #expect(messages.map(\.reasoningContent) == ["In use reasoning"])
        let attachments = storage.attachment(for: fixture.message)
        #expect(attachments.map(\.id) == [fixture.attachment])
        #expect(attachments.map { [$0.data, $0.previewImageData, $0.imageRepresentation] } == [fixture.blobs])
        #expect(attachments.map(\.representedDocument) == ["In use text"])
    }

    func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("StorageExportRemovedContentTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func text(_ value: Int) -> Data {
        Data(String(value).utf8)
    }
}

// MARK: - Export and import

private extension StorageExportRemovedContentTests {
    /// The conversations, messages and attachments of a database, removed ones included.
    struct Objects {
        var conversations: [String: Conversation] = [:]
        var messages: [String: Message] = [:]
        var attachments: [String: Attachment] = [:]
        /// Every column of every row and queued upload, to compare two readings.
        var contents: [String: Data] = [:]
    }

    /// Reads every row through Storage. Each row has a queued upload, which is how removed rows are reached.
    func objects(in storage: Storage) throws -> Objects {
        let lastQueueID = try #require(storage.pendingUploadList(tables: Self.tables).map(\.id).max())
        let queue = storage.pendingUploadList(queueIds: Array(0 ... lastQueueID), queryRealObject: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        var objects = Objects()
        for entry in queue {
            let state = "\(entry.tableName) \(entry.objectId) \(entry.changes) \(entry.state) \(entry.failCount)"
            objects.contents["UploadQueue \(entry.id)"] = Data(state.utf8)
            let key = "\(entry.tableName) \(entry.objectId)"
            switch entry.realObject {
            case let conversation as Conversation:
                objects.conversations[conversation.objectId] = conversation
                objects.contents[key] = try encoder.encode(conversation)
            case let message as Message:
                objects.messages[message.objectId] = message
                objects.contents[key] = try encoder.encode(message)
            case let attachment as Attachment:
                objects.attachments[attachment.objectId] = attachment
                objects.contents[key] = try encoder.encode(attachment)
            default:
                Issue.record("no row for the queued upload of \(key)")
            }
        }
        return objects
    }

    /// Exports the fixture and hands over the rows of the database in use as read before the export,
    /// a copy of its files from after the export, and the exported files.
    func withExport(_ body: (Fixture, _ source: Objects, _ live: URL, _ exported: URL) throws -> Void) throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let fixture: Fixture
        let source: Objects
        let exported: URL
        do {
            let storage = try Storage.makeForTesting(databaseDir: directory)
            fixture = try makeFixture(in: storage)
            source = try objects(in: storage)
            #expect(source.conversations.count == 3)
            #expect(source.messages.count == 4)
            #expect(source.attachments.count == 4)
            exported = try storage.exportDatabase().get()
            // the export only reads the database in use
            #expect(try objects(in: storage).contents == source.contents)
        }
        defer { try? FileManager.default.removeItem(at: exported) }

        // Storage is released by now, so nothing writes to the files while they are copied.
        let live = try copy(of: directory)
        defer { try? FileManager.default.removeItem(at: live) }

        try body(fixture, source, live, exported)
    }

    /// An export of the fixture, imported over another database the way the app does it.
    @MainActor
    final class ImportedExport {
        let fixture: Fixture
        let storage: Storage
        private let directories: [URL]

        init(_ tests: StorageExportRemovedContentTests) async throws {
            let directory = try tests.makeDirectory()
            let targetDirectory = try tests.makeDirectory()
            let source = try Storage.makeForTesting(databaseDir: directory)
            fixture = try tests.makeFixture(in: source)

            let archive = try source.exportZipFile().get()
            directories = [directory, targetDirectory, archive.deletingLastPathComponent()]

            let target = try Storage.makeForTesting(name: "Target", databaseDir: targetDirectory)
            _ = target.conversationMake { $0.update(\.title, to: "Replaced") }
            let result = await withCheckedContinuation { continuation in
                target.importDatabase(from: archive) { continuation.resume(returning: $0) }
            }
            try result.get()

            storage = try Storage.makeForTesting(name: "Imported", databaseDir: targetDirectory)
        }

        func tearDown() {
            for directory in directories {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}

// MARK: - Sync engine

private extension StorageExportRemovedContentTests {
    func makeEngine(storage: Storage) -> SyncEngine {
        SyncEngine(
            storage: storage,
            containerIdentifier: "iCloud.wiki.qaq.flowdown.tests.\(UUID().uuidString)",
            mode: .mock,
            automaticallySync: false,
        )
    }

    func makeMock(engine: SyncEngine) -> MockSyncEngine {
        let container = MockCloudContainer.createContainer(
            identifier: "iCloud.wiki.qaq.flowdown.tests.\(UUID().uuidString)",
        )
        return MockSyncEngine(
            database: container.privateCloudDatabase,
            parentSyncEngine: engine,
            state: MockSyncEngineState(),
            delegate: engine,
        )
    }

    /// The pending changes SyncEngine.scheduleUploadIfNeeded adds for the queued uploads. That method
    /// does nothing in the simulator, where CloudKit sync is not supported, so its mapping is repeated here.
    func pendingChanges(
        for queue: [UploadQueue],
        deletionsAsSaves: Bool,
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        queue.map { entry in
            if entry.changes == .delete, !deletionsAsSaves {
                return .deleteRecord(CKRecord.ID(recordName: entry.ckRecordID, zoneID: Self.zoneID))
            }
            let separator = SyncEngine.CKRecordSentQueueIdSeparator
            return .saveRecord(CKRecord.ID(
                recordName: "\(entry.id)\(separator)\(entry.objectId)\(separator)\(Storage.deviceId)",
                zoneID: Self.zoneID,
            ))
        }
    }

    func recordObjectId(_ record: CKRecord) -> String? {
        objectId(record.recordID)
    }

    func objectId(_ recordID: CKRecord.ID) -> String? {
        UploadQueue.parseCKRecordID(recordID.recordName)?.objectId
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
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            // SQLite rebuilds the shared memory file from the write-ahead log
            .filter { !$0.lastPathComponent.hasSuffix("-shm") }
        // the write-ahead log goes first: it holds the newest pages whatever was moved to the database since
        for file in files.sorted(by: { $0.lastPathComponent.hasSuffix("-wal") && !$1.lastPathComponent.hasSuffix("-wal") }) {
            try FileManager.default.copyItem(at: file, to: destination.appendingPathComponent(file.lastPathComponent))
        }
        return destination
    }

    /// The columns Storage writes as JSON. The export reads each row and writes it again, and JSONEncoder
    /// writes the keys of an object in no fixed order, so the same value can be stored as different bytes:
    /// {"queries":["query"],"id":"A"} in one database and {"id":"A","queries":["query"]} in the other.
    /// The key order is the only difference, so these columns are compared with their keys sorted.
    /// Every other column is compared byte for byte.
    static let jsonColumns: Set<String> = ["documentNodes", "webSearchStatus", "toolStatus"]

    /// The cells the query reads differently from the two databases, as "row column", and the row counts
    /// and column names where those differ. Empty when both hold the same rows.
    func differences(_ sql: String, between first: URL, and second: URL) throws -> [String] {
        let firstColumns = try columns(sql, in: first)
        let secondColumns = try columns(sql, in: second)
        guard firstColumns == secondColumns else {
            return ["columns \(firstColumns) and \(secondColumns)"]
        }
        let firstRows = try rows(sql, in: first)
        let secondRows = try rows(sql, in: second)
        guard firstRows.count == secondRows.count else {
            return ["\(firstRows.count) and \(secondRows.count) rows"]
        }

        var result: [String] = []
        for (row, (firstRow, secondRow)) in zip(firstRows, secondRows).enumerated() {
            for (column, name) in firstColumns.enumerated() {
                let isJSON = Self.jsonColumns.contains(name)
                let firstCell = isJSON ? try sortedKeys(firstRow[column]) : firstRow[column]
                let secondCell = isJSON ? try sortedKeys(secondRow[column]) : secondRow[column]
                if firstCell != secondCell {
                    result.append("\(row) \(name)")
                }
            }
        }
        return result
    }

    /// The same JSON with the keys of every object in order.
    func sortedKeys(_ json: Data) throws -> Data {
        let value = try JSONSerialization.jsonObject(with: json, options: .fragmentsAllowed)
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
    }

    /// The names of the columns a query reads.
    func columns(_ sql: String, in directory: URL) throws -> [String] {
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
        return (0 ..< sqlite3_column_count(statement)).map { String(cString: sqlite3_column_name(statement, $0)) }
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

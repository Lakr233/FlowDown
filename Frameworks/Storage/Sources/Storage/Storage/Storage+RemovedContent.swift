//
//  Storage+RemovedContent.swift
//  Storage
//

import Foundation
import MarkdownParser
import WCDBSwift

// A removed Message or Attachment row stays in the database for 30 days so that the deletion can
// reach iCloud and the other devices. Nothing reads its content in that time, so the content is
// emptied here. The row keeps its identity, its dates and its removed flag.

extension Message.WebSearchStatus {
    /// The bytes written to the column of a removed message. The id is fixed and the keys are
    /// sorted, so the same bytes are written every time and a row holding them is left alone.
    static let removedColumnValue: Data = {
        var status = Message.WebSearchStatus()
        status.id = Storage.removedContentIdentifier
        return Storage.removedColumnValue(of: status)
    }()
}

extension Message.ToolStatus {
    /// See `Message.WebSearchStatus.removedColumnValue`.
    static let removedColumnValue: Data = {
        var status = Message.ToolStatus()
        status.id = Storage.removedContentIdentifier
        return Storage.removedColumnValue(of: status)
    }()
}

extension Storage {
    static let removedContentIdentifier = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))

    /// An empty list of document nodes as the column stores it.
    static let removedDocumentNodesColumnValue = Data("[]".utf8)

    static func removedColumnValue(of value: some Encodable) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        do {
            return try encoder.encode(value)
        } catch {
            fatalError("unable to encode the empty value of a removed row: \(error)")
        }
    }

    /// Empties the content columns of removed Message and Attachment rows.
    ///
    /// Only the content columns are written. `modified` stays as it is, because it dates the
    /// deletion for the 30 day purge and for sync, and nothing is added to the upload queue.
    /// A row that is already empty is not matched, so it is not written again. The three JSON
    /// columns are matched by length: a search or tool status as long as the empty one is left
    /// alone, and it has no room for a query, a result, a tool name or a tool message.
    ///
    /// - Parameter modifiedAfter: Rows removed before this date are left out. The caller has just
    ///   purged them, and the lower bound lets the index on `modified` find the rest.
    /// - Returns: The number of rows emptied in each table.
    @discardableResult
    func clearRemovedContent(
        modifiedAfter: Date,
        handle: Handle,
    ) throws -> (messages: Int, attachments: Int) {
        let message = Message.Properties.self
        try handle.update(
            table: Message.tableName,
            on: [
                message.document,
                message.documentNodes,
                message.reasoningContent,
                message.webSearchStatus,
                message.toolStatus,
                message.metadata,
            ],
            with: [
                "",
                Storage.removedDocumentNodesColumnValue,
                "",
                Message.WebSearchStatus.removedColumnValue,
                Message.ToolStatus.removedColumnValue,
                nil,
            ],
            where: message.modified > modifiedAfter
                && message.removed == true
                && (message.document != ""
                    || message.reasoningContent != ""
                    || message.metadata.isNotNull()
                    // These three are BLOB columns. A value compared with one is written into the
                    // statement as text, which SQLite never finds equal to a BLOB, so the lengths
                    // are compared instead.
                    || message.documentNodes.length() != Storage.removedDocumentNodesColumnValue.count
                    || message.webSearchStatus.length() != Message.WebSearchStatus.removedColumnValue.count
                    || message.toolStatus.length() != Message.ToolStatus.removedColumnValue.count),
        )
        let messages = handle.changes

        let attachment = Attachment.Properties.self
        try handle.update(
            table: Attachment.tableName,
            on: [
                attachment.data,
                attachment.previewImageData,
                attachment.imageRepresentation,
                attachment.representedDocument,
            ],
            with: [Data(), Data(), Data(), ""],
            where: attachment.modified > modifiedAfter
                && attachment.removed == true
                && (attachment.data.length() > 0
                    || attachment.previewImageData.length() > 0
                    || attachment.imageRepresentation.length() > 0
                    || attachment.representedDocument != ""),
        )
        return (messages, handle.changes)
    }
}

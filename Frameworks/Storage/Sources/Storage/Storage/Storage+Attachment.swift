//
//  Created by ktiays on 2025/2/24.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation
import WCDBSwift

public extension Storage {
    func attachment(for messageID: String) -> [Attachment] {
        (
            try? db.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId == messageID && Attachment.Properties.removed == false,
                orderBy: [
                    Attachment.Properties.creation
                        .order(.ascending),
                ],
            ),
        ) ?? []
    }

    typealias AttachmentMakeInitDataBlock = (Attachment) -> Void
    func attachmentMake(
        with messageID: String,
        skipSave: Bool = false,
        block: AttachmentMakeInitDataBlock? = nil
    ) -> Attachment {
        let attachment = Attachment(deviceId: Self.deviceId)
        attachment.messageId = messageID

        if let block {
            block(attachment)
        }

        attachment.creation = .now
        attachment.modified = attachment.creation

        if skipSave {
            return attachment
        }

        try? runTransaction {
            try $0.insert([attachment], intoTable: Attachment.tableName)
            try self.pendingUploadEnqueue(sources: [(attachment, .insert)], handle: $0)
        }
        return attachment
    }

    func attachmentsUpdate(_ attachments: [Attachment]) {
        guard !attachments.isEmpty else {
            return
        }

        try? putSyncable(attachments)
    }

    func attachmentsMarkDelete(messageIds: [Message.ID], handle: Handle? = nil) throws {
        guard !messageIds.isEmpty else {
            return
        }

        try runTransaction(handle: handle) { [weak self] in
            guard let self else { return }

            let objects: [Attachment] = try $0.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.messageId.in(messageIds)
                    && Attachment.Properties.removed == false,
            )

            guard !objects.isEmpty else {
                return
            }

            let modified = Date.now

            for object in objects {
                object.removed = true
                object.markModified(modified)
            }

            let update = StatementUpdate().update(table: Attachment.tableName)
                .set(Attachment.Properties.removed)
                .to(true)
                .set(Attachment.Properties.modified)
                .to(modified)
                .where(Attachment.Properties.messageId.in(messageIds))

            try $0.exec(update)

            try pendingUploadEnqueue(sources: objects.map { ($0, .delete) }, handle: $0)
        }
    }

    /// - Parameter handle: The handle of the enclosing transaction.
    func attachmentsMarkDelete(handle: Handle) throws {
        try runTransaction(handle: handle) { [weak self] in
            guard let self else { return }

            let objects: [Attachment] = try $0.getObjects(
                fromTable: Attachment.tableName,
                where: Attachment.Properties.removed == false,
            )

            guard !objects.isEmpty else {
                return
            }

            let modified = Date.now

            for object in objects {
                object.removed = true
                object.markModified(modified)
            }

            let update = StatementUpdate().update(table: Attachment.tableName)
                .set(Attachment.Properties.removed)
                .to(true)
                .set(Attachment.Properties.modified)
                .to(modified)
                .where(Attachment.Properties.removed == false)

            try $0.exec(update)

            try pendingUploadEnqueue(sources: objects.map { ($0, .delete) }, handle: $0)
        }
    }
}

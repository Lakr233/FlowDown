//
//  Storage+ChatTemplate.swift
//  Storage
//
//  Created by GPT-5 Codex on 2025/11/05.
//

import Foundation
import WCDBSwift

public extension Storage {
    func chatTemplateList(includeRemoved: Bool = false) -> [ChatTemplateObject] {
        let condition: Condition?
        if includeRemoved {
            condition = nil
        } else {
            condition = ChatTemplateObject.Properties.removed == false
        }

        let order: [OrderBy] = [
            ChatTemplateObject.Properties.sortIndex.order(.ascending),
            ChatTemplateObject.Properties.creation.order(.ascending),
        ]

        return (
            try? db.getObjects(
                fromTable: ChatTemplateObject.tableName,
                where: condition,
                orderBy: order
            )
        ) ?? []
    }

    func chatTemplate(identifier: ChatTemplateObject.ID) -> ChatTemplateObject? {
        try? db.getObject(
            fromTable: ChatTemplateObject.tableName,
            where: ChatTemplateObject.Properties.objectId == identifier
        )
    }

    func chatTemplateSave(_ object: ChatTemplateObject) {
        chatTemplateSave([object])
    }

    func chatTemplateSave(_ objects: [ChatTemplateObject]) {
        guard !objects.isEmpty else { return }

        let modified = Date.now

        try? runTransaction { [weak self] handle in
            guard let self else { return }

            let diff = try diffSyncable(objects: objects, handle: handle)
            guard !diff.isEmpty else { return }

            diff.insert.forEach { $0.markModified($0.creation) }

            try handle.insertOrReplace(diff.insertOrReplace(), intoTable: ChatTemplateObject.tableName)

            if !diff.deleted.isEmpty {
                let deletedIds = diff.deleted.map(\.objectId)
                let update = StatementUpdate().update(table: ChatTemplateObject.tableName)
                    .set(ChatTemplateObject.Properties.removed)
                    .to(true)
                    .set(ChatTemplateObject.Properties.modified)
                    .to(modified)
                    .where(ChatTemplateObject.Properties.objectId.in(deletedIds))
                try handle.exec(update)
            }

            var changes: [(source: any Syncable, changes: UploadQueue.Changes)] = []
            changes.append(contentsOf: diff.insert.map { ($0, .insert) })
            changes.append(contentsOf: diff.updated.map { ($0, .update) })
            changes.append(contentsOf: diff.deleted.map { ($0, .delete) })

            changes.sort { lhs, rhs in
                guard
                    let left = lhs.source as? ChatTemplateObject,
                    let right = rhs.source as? ChatTemplateObject
                else { return false }
                return left.modified < right.modified
            }

            guard !changes.isEmpty else { return }
            try pendingUploadEnqueue(sources: changes, handle: handle)
        }

        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func chatTemplateMarkDelete(identifier: ChatTemplateObject.ID) {
        try? runTransaction { [weak self] handle in
            guard let self else { return }
            guard let object: ChatTemplateObject = try handle.getObject(
                fromTable: ChatTemplateObject.tableName,
                where: ChatTemplateObject.Properties.objectId == identifier
            ) else {
                return
            }

            object.removed = true
            object.markModified()

            try handle.insertOrReplace([object], intoTable: ChatTemplateObject.tableName)
            try pendingUploadEnqueue(sources: [(object, .delete)], handle: handle)
        }

        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func chatTemplateRemoveAll() {
        try? db.run { handle -> Bool in
            do {
                try handle.delete(fromTable: ChatTemplateObject.tableName)
                return true
            } catch {
                Logger.database.error("chatTemplateRemoveAll error: \(error.localizedDescription)")
                return false
            }
        }
    }
}

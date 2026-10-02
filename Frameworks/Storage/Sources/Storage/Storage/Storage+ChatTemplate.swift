//
//  Storage+ChatTemplate.swift
//  Storage
//
//  Created by Assistant on 2025/12/07.
//

import Foundation
import WCDBSwift

public extension Storage {
    func templateList() -> [ChatTemplateRecord] {
        (
            try? db.getObjects(
                fromTable: ChatTemplateRecord.tableName,
                where: ChatTemplateRecord.Properties.removed == false,
                orderBy: [
                    ChatTemplateRecord.Properties.sortIndex.order(.ascending),
                    ChatTemplateRecord.Properties.creation.order(.ascending),
                ],
            ),
        ) ?? []
    }

    func template(with identifier: ChatTemplateRecord.ID) -> ChatTemplateRecord? {
        try? db.getObject(
            fromTable: ChatTemplateRecord.tableName,
            where: ChatTemplateRecord.Properties.objectId == identifier
                && ChatTemplateRecord.Properties.removed == false,
        )
    }

    func templateSave(record: ChatTemplateRecord) {
        templateSave(records: [record])
    }

    func templateSave(records: [ChatTemplateRecord]) {
        guard !records.isEmpty else {
            return
        }

        try? putSyncable(records)

        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func templateMarkDelete(identifier: ChatTemplateRecord.ID) {
        guard !identifier.isEmpty else {
            return
        }

        try? runTransaction { [weak self] in
            guard let self else { return }

            guard let template: ChatTemplateRecord = try? $0.getObject(
                fromTable: ChatTemplateRecord.tableName,
                where: ChatTemplateRecord.Properties.objectId == identifier,
            ) else {
                return
            }

            template.removed = true
            template.markModified()

            let update = StatementUpdate().update(table: ChatTemplateRecord.tableName)
                .set(ChatTemplateRecord.Properties.removed)
                .to(true)
                .set(ChatTemplateRecord.Properties.modified)
                .to(template.modified)
                .where(ChatTemplateRecord.Properties.objectId == identifier)
            try $0.exec(update)

            try pendingUploadEnqueue(sources: [(template, .delete)], handle: $0)
        }
    }

    func templateReorder(_ orderedIDs: [ChatTemplateRecord.ID]) {
        guard !orderedIDs.isEmpty else {
            return
        }

        try? runTransaction { [weak self] in
            guard let self else { return }
            let templates: [ChatTemplateRecord] = try $0.getObjects(
                fromTable: ChatTemplateRecord.tableName,
                where: ChatTemplateRecord.Properties.objectId.in(orderedIDs)
                    && ChatTemplateRecord.Properties.removed == false,
            )
            guard !templates.isEmpty else {
                return
            }

            let now = Date.now
            var map = [String: ChatTemplateRecord]()
            for item in templates {
                map[item.objectId] = item
            }

            var updates: [ChatTemplateRecord] = []
            for (index, id) in orderedIDs.enumerated() {
                guard let item = map[id] else { continue }
                let newIndex = Double(index)
                guard item.sortIndex != newIndex else { continue }
                item.sortIndex = newIndex
                item.markModified(now)
                updates.append(item)
            }

            guard !updates.isEmpty else {
                return
            }

            try $0.insertOrReplace(updates, intoTable: ChatTemplateRecord.tableName)
            try pendingUploadEnqueue(sources: updates.map { ($0, .update) }, handle: $0)
        }

        Task {
            try? await syncEngine?.sendChanges()
        }
    }

    func templateNextSortIndex() -> Double {
        let select = StatementSelect()
            .select(ChatTemplateRecord.Properties.sortIndex.max())
            .from(ChatTemplateRecord.tableName)
            .where(ChatTemplateRecord.Properties.removed == false)

        let row = try? db.getRow(from: select)

        let value = row?[0].doubleValue ?? -1
        return value + 1
    }
}

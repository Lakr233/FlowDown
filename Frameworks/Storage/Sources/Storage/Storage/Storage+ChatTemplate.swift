//
//  Storage+ChatTemplate.swift
//  Storage
//
//  Created by GPT-5 Codex on 2025/11/05.
//

import Foundation
import WCDBSwift

public extension Storage {
    enum ChatTemplateError: Error, LocalizedError {
        case duplicate(String)
        case notFound(String)
        case operationFailed(String)

        public var errorDescription: String? {
            switch self {
            case let .duplicate(objectId):
                "Template with ID \(objectId) already exists"
            case let .notFound(objectId):
                "Template with ID \(objectId) was not found"
            case let .operationFailed(message):
                "Template operation failed: \(message)"
            }
        }
    }

    func fetchAllChatTemplates(includeRemoved: Bool = false) throws -> [ChatTemplateRecord] {
        do {
            return try db.getObjects(
                fromTable: ChatTemplateRecord.tableName,
                where: includeRemoved ? nil : ChatTemplateRecord.Properties.removed == false,
                orderBy: [
                    ChatTemplateRecord.Properties.sortIndex.order(.ascending),
                    ChatTemplateRecord.Properties.creation.order(.ascending),
                ]
            )
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func fetchChatTemplate(id: String) throws -> ChatTemplateRecord? {
        do {
            return try db.getObject(
                fromTable: ChatTemplateRecord.tableName,
                where: ChatTemplateRecord.Properties.objectId == id
            )
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func insertChatTemplate(_ template: ChatTemplateRecord) throws {
        try insertChatTemplates([template])
    }

    func insertChatTemplates(_ templates: [ChatTemplateRecord]) throws {
        guard !templates.isEmpty else { return }

        do {
            try runTransaction { handle in
                var sources: [(any Syncable, UploadQueue.Changes)] = []

                for template in templates {
                    let exists: ChatTemplateRecord? = try handle.getObject(
                        fromTable: ChatTemplateRecord.tableName,
                        where: ChatTemplateRecord.Properties.objectId == template.objectId
                    )

                    if let exists {
                        template.sortIndex = exists.sortIndex
                        template.creation = exists.creation
                        template.deviceId = exists.deviceId
                        template.removed = false
                        template.markModified()
                        try handle.insertOrReplace([template], intoTable: ChatTemplateRecord.tableName)
                        sources.append((template, .update))
                    } else {
                        template.markModified(template.creation)
                        try handle.insertOrReplace([template], intoTable: ChatTemplateRecord.tableName)
                        sources.append((template, .insert))
                    }
                }

                if !sources.isEmpty {
                    try pendingUploadEnqueue(sources: sources, handle: handle)
                }
            }
        } catch let error as ChatTemplateError {
            throw error
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func updateChatTemplate(_ template: ChatTemplateRecord) throws {
        do {
            try runTransaction { handle in
                guard let existing: ChatTemplateRecord = try handle.getObject(
                    fromTable: ChatTemplateRecord.tableName,
                    where: ChatTemplateRecord.Properties.objectId == template.objectId
                ) else {
                    throw ChatTemplateError.notFound(template.objectId)
                }

                template.creation = existing.creation
                template.deviceId = existing.deviceId

                template.markModified()
                try handle.insertOrReplace([template], intoTable: ChatTemplateRecord.tableName)
                try pendingUploadEnqueue(sources: [(template, .update)], handle: handle)
            }
        } catch let error as ChatTemplateError {
            throw error
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func markChatTemplateRemoved(id: String) throws {
        do {
            try runTransaction { handle in
                guard let template: ChatTemplateRecord = try handle.getObject(
                    fromTable: ChatTemplateRecord.tableName,
                    where: ChatTemplateRecord.Properties.objectId == id
                ) else {
                    throw ChatTemplateError.notFound(id)
                }

                template.removed = true
                template.markModified()

                try handle.insertOrReplace([template], intoTable: ChatTemplateRecord.tableName)
                try pendingUploadEnqueue(sources: [(template, .delete)], handle: handle)
            }
        } catch let error as ChatTemplateError {
            throw error
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func updateChatTemplateOrders(_ orderMap: [String: Int]) throws {
        guard !orderMap.isEmpty else { return }

        do {
            try runTransaction { handle in
                let ids = orderMap.keys.map { $0 }
                let templates: [ChatTemplateRecord] = try handle.getObjects(
                    fromTable: ChatTemplateRecord.tableName,
                    where: ChatTemplateRecord.Properties.objectId.in(ids)
                        && ChatTemplateRecord.Properties.removed == false
                )

                guard !templates.isEmpty else { return }

                let now = Date.now
                var updated: [ChatTemplateRecord] = []

                for template in templates {
                    guard let newOrder = orderMap[template.objectId], template.sortIndex != newOrder else { continue }
                    template.sortIndex = newOrder
                    template.markModified(now)
                    updated.append(template)
                }

                guard !updated.isEmpty else { return }

                try handle.insertOrReplace(updated, intoTable: ChatTemplateRecord.tableName)
                try pendingUploadEnqueue(sources: updated.map { ($0, .update) }, handle: handle)
            }
        } catch let error as ChatTemplateError {
            throw error
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }

    func deleteAllChatTemplates() throws {
        do {
            try runTransaction { handle in
                try handle.delete(fromTable: ChatTemplateRecord.tableName)
            }
        } catch {
            throw ChatTemplateError.operationFailed(error.localizedDescription)
        }
    }
}

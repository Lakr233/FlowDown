//
//  Storage+Memory.swift
//  Storage
//
//  Created by Alan Ye on 8/14/25.
//

import Foundation
import WCDBSwift

public extension Storage {
    enum MemoryError: Error, LocalizedError {
        case insertFailed(String)
        case retrieveFailed(String)
        case deleteFailed(String)
        case memoryNotFound(String)
        case databaseError(String)

        var localizedDescription: String {
            switch self {
            case let .insertFailed(message):
                "Failed to insert memory: \(message)"
            case let .retrieveFailed(message):
                "Failed to retrieve memories: \(message)"
            case let .deleteFailed(message):
                "Failed to delete memory: \(message)"
            case let .memoryNotFound(id):
                "Memory with ID \(id) not found"
            case let .databaseError(message):
                "Database error: \(message)"
            }
        }
    }

    func insertMemory(_ memory: Memory) throws {
        try insertMemory(memorys: [memory])
    }

    func insertMemory(memorys: [Memory]) throws {
        guard !memorys.isEmpty else {
            return
        }

        do {
            try putSyncable(memorys)
        } catch {
            throw MemoryError.insertFailed(error.localizedDescription)
        }
    }

    func getAllMemories() throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemoriesWithLimit(_ limit: Int) throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
                limit: limit,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemory(id: String) throws -> Memory? {
        do {
            return try db.getObject(
                fromTable: Memory.tableName,
                where: Memory.Properties.objectId == id && Memory.Properties.removed == false,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func searchMemories(query: String, limit: Int = 20) throws -> [Memory] {
        do {
            return try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false && Memory.Properties.content.like("%\(query)%"),
                orderBy: [
                    Memory.Properties.creation.order(.descending),
                ],
                limit: limit,
            )
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func getMemoryCount() throws -> Int {
        do {
            let objects: [Memory] = try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false
            )
            return objects.count
        } catch {
            throw MemoryError.retrieveFailed(error.localizedDescription)
        }
    }

    func updateMemory(_ memory: Memory) throws {
        do {
            let existingMemory = try db.getObject(
                fromTable: Memory.tableName,
                where: Memory.Properties.objectId == memory.objectId,
            ) as Memory?

            guard existingMemory != nil else {
                throw MemoryError.memoryNotFound(memory.objectId)
            }

            try db.insertOrReplace([memory], intoTable: Memory.tableName)
            try pendingUploadEnqueue(sources: [(memory, .update)])

        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.insertFailed(error.localizedDescription)
        }
    }

    func deleteMemory(id: Memory.ID) throws {
        do {
            let existingMemory: Memory? = try db.getObject(
                fromTable: Memory.tableName,
                where: Memory.Properties.objectId == id,
            )

            guard let existingMemory else {
                throw MemoryError.memoryNotFound(id)
            }

            existingMemory.markModified()

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(existingMemory.modified)
                .where(Memory.Properties.objectId == id)

            try db.exec(update)

            try pendingUploadEnqueue(sources: [(existingMemory, .delete)])

        } catch let error as MemoryError {
            throw error
        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }

    func deleteAllMemories() throws {
        do {
            let memorys: [Memory] = try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
            )

            guard !memorys.isEmpty else {
                return
            }

            let deletedIds = memorys.map(\.objectId)
            let modified = Date.now
            memorys.forEach { $0.markModified(modified) }

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(modified)
                .where(Memory.Properties.objectId.in(deletedIds))

            try db.exec(update)

            try pendingUploadEnqueue(sources: memorys.map { ($0, .delete) })
        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }

    func deleteOldMemories(keepCount: Int) throws {
        do {
            let allMemories: [Memory] = try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false
            )

            let totalCount = allMemories.count
            guard totalCount > keepCount else { return }

            let memoriesToDelete: [Memory] = try db.getObjects(
                fromTable: Memory.tableName,
                where: Memory.Properties.removed == false,
                orderBy: [
                    Memory.Properties.creation.order(.ascending),
                ],
                limit: totalCount - keepCount,
            )

            guard !memoriesToDelete.isEmpty else {
                return
            }

            let deletedIds = memoriesToDelete.map(\.objectId)
            let modified = Date.now
            memoriesToDelete.forEach { $0.markModified(modified) }

            let update = StatementUpdate().update(table: Memory.tableName)
                .set(Memory.Properties.removed)
                .to(true)
                .set(Memory.Properties.modified)
                .to(modified)
                .where(Memory.Properties.objectId.in(deletedIds))

            try db.exec(update)

            try pendingUploadEnqueue(sources: memoriesToDelete.map { ($0, .delete) })

        } catch {
            throw MemoryError.deleteFailed(error.localizedDescription)
        }
    }
}

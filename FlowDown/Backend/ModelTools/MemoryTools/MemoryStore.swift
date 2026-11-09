//
//  MemoryStore.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import Foundation
import Storage

@MainActor
class MemoryStore {
    static let shared = MemoryStore()

    private let queue = DispatchQueue(label: "wiki.qaq.MemoryStore", qos: .utility)
    private let maxMemoryCount = 1000
    private let maxMemoryLength = 2000
    nonisolated static let memoryLimitRange = 1 ... 100

    private init() {}

    private func clampedLimit(_ limit: Int) -> Int {
        min(max(limit, Self.memoryLimitRange.lowerBound), Self.memoryLimitRange.upperBound)
    }

    private func validatedContent(_ content: String) throws -> String {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw MemoryStoreError.invalidContent(String(localized: "Memory content cannot be empty"))
        }

        guard trimmedContent.count <= maxMemoryLength else {
            throw MemoryStoreError.invalidContent(
                String(localized: "Memory content exceeds maximum length of \(maxMemoryLength) characters")
            )
        }
        return trimmedContent
    }

    /// Runs `body` against the database on `queue`. A `MemoryStoreError` thrown by
    /// `body` passes through unchanged; any other failure becomes `storageError`.
    private func onQueue<T>(_ body: @escaping @Sendable (Storage) throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try body(Storage.db()))
                } catch let error as MemoryStoreError {
                    continuation.resume(throwing: error)
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Public Async API

    func storeAsync(content: String, conversationId: String? = nil) async throws -> Memory {
        let trimmedContent = try validatedContent(content)

        return try await onQueue { storage in
            let memory = Memory(
                deviceId: Storage.deviceId,
                content: trimmedContent,
                conversationId: conversationId
            )
            try storage.insertMemory(memory)

            try storage.deleteOldMemories(keepCount: self.maxMemoryCount)

            return memory
        }
    }

    func getAllMemoriesAsync() async throws -> [Memory] {
        try await onQueue { try $0.getAllMemories() }
    }

    func getMemoriesWithLimit(_ limit: Int) async throws -> [Memory] {
        let safeLimit = clampedLimit(limit)
        return try await onQueue { try $0.getMemoriesWithLimit(safeLimit) }
    }

    func searchMemories(query: String, limit: Int = 20) async throws -> [Memory] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await getAllMemoriesAsync()
        }

        let safeLimit = clampedLimit(limit)
        return try await onQueue { try $0.searchMemories(query: trimmedQuery, limit: safeLimit) }
    }

    func updateMemoryAsync(id: String, newContent: String) async throws {
        let trimmedContent = try validatedContent(newContent)

        try await onQueue { storage in
            guard let existingMemory = try storage.getMemory(id: id) else {
                throw MemoryStoreError.memoryNotFound(id)
            }

            existingMemory.update(\.content, to: trimmedContent)
            try storage.updateMemory(existingMemory)
        }
    }

    func deleteMemoryAsync(id: String) async throws {
        try await onQueue { try $0.deleteMemory(id: id) }
    }

    func deleteAllMemoriesAsync() async throws {
        try await onQueue { try $0.deleteAllMemories() }
    }

    // MARK: - Sync API

    func recallToolText() -> String {
        do {
            return Self.render(try Storage.db().getAllMemories(), includeIdentifiers: false)
        } catch {
            return "Failed to retrieve memories: \(error.localizedDescription)"
        }
    }

    func listToolText(limit: Int) -> String {
        do {
            let storage = try Storage.db()
            return Self.render(
                try storage.getMemoriesWithLimit(clampedLimit(limit)),
                includeIdentifiers: true,
            )
        } catch {
            return "Failed to retrieve memories: \(error.localizedDescription)"
        }
    }

    /// Renders the memory list handed to the model. `includeIdentifiers` adds the
    /// ids that the update and delete tools require.
    private static func render(_ memories: [Memory], includeIdentifiers: Bool) -> String {
        guard !memories.isEmpty else { return "No memories stored yet." }
        var result = "Stored memories:\n\n"
        for (index, memory) in memories.enumerated() {
            let timestamp = ISO8601DateFormatter().string(from: memory.creation)
            if includeIdentifiers {
                result += "\(index + 1). ID: \(memory.id)\n   [\(timestamp)] \(memory.content)\n\n"
            } else {
                result += "\(index + 1). [\(timestamp)] \(memory.content)\n"
            }
        }
        return result
    }

    func updateMemory(id: String, newContent: String) -> String {
        do {
            let trimmedContent = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedContent.isEmpty else {
                return "Error: Memory content cannot be empty"
            }

            guard trimmedContent.count <= maxMemoryLength else {
                return "Error: Memory content exceeds maximum length of \(maxMemoryLength) characters"
            }

            let storage = try Storage.db()
            guard let existingMemory = try storage.getMemory(id: id) else {
                return "Memory with ID \(id) not found."
            }

            existingMemory.update(\.content, to: trimmedContent)
            try storage.updateMemory(existingMemory)

            return "Memory updated successfully."
        } catch {
            return "Failed to update memory: \(error.localizedDescription)"
        }
    }

    func deleteMemory(id: String, reason: String? = nil) -> String {
        do {
            let storage = try Storage.db()
            try storage.deleteMemory(id: id)

            if let reason {
                return "Memory deleted successfully. Reason: \(reason)"
            } else {
                return "Memory deleted successfully."
            }
        } catch let error as Storage.MemoryError {
            return error.localizedDescription
        } catch {
            return "Failed to delete memory: \(error.localizedDescription)"
        }
    }

    /// Fire-and-forget insert for callers that have nowhere to surface a failure.
    func store(content: String, conversationId: String? = nil) {
        Task {
            do {
                _ = try await storeAsync(content: content, conversationId: conversationId)
            } catch {
                Logger.database.errorFile("MemoryStore failed to store memory: \(error)")
            }
        }
    }

    func formattedProactiveMemoryContext(
        for scope: MemoryProactiveProvisionScope = MemoryProactiveProvisionSetting.currentScope,
    ) async -> String? {
        if case .none = scope.filter { return nil }

        do {
            let memories = try await getAllMemoriesAsync()

            let filteredMemories: [Memory]
            switch scope.filter {
            case .none:
                assertionFailure()
                return nil
            case let .timeInterval(interval):
                let threshold = Date().addingTimeInterval(-interval)
                filteredMemories = memories.filter { $0.creation >= threshold }
            case let .count(limit):
                filteredMemories = Array(memories.prefix(limit))
            case .all:
                filteredMemories = memories
            }

            guard !filteredMemories.isEmpty else { return nil }

            let header = String(localized: "Proactive Memory Context")
            let scopeDescription = String(localized: scope.briefDescription)
            let scopeLine = String(localized: "Scope: \(scopeDescription)")

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            let body = filteredMemories.enumerated().map { index, memory -> String in
                let timestamp = dateFormatter.string(from: memory.creation)
                return "\(index + 1). [\(timestamp)] \(memory.content)"
            }
            .joined(separator: "\n")

            return [header, scopeLine, "", body].joined(separator: "\n")
        } catch {
            Logger.database.errorFile("MemoryStore failed to build proactive memory context: \(error)")
            return nil
        }
    }
}

// MARK: - Error Types

enum MemoryStoreError: Error, LocalizedError {
    case invalidContent(String)
    case memoryNotFound(String)
    case storageError(String)

    var errorDescription: String? {
        switch self {
        case let .invalidContent(message):
            String(localized: "Invalid content: \(message)")
        case let .memoryNotFound(id):
            String(localized: "Memory not found: \(id)")
        case let .storageError(message):
            String(localized: "Storage error: \(message)")
        }
    }
}

//
//  MemoryStore.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import Combine
import Foundation
import Storage

@MainActor
public class MemoryStore: ObservableObject {
    public static let shared = MemoryStore()

    private let queue = DispatchQueue(label: "wiki.qaq.MemoryStore", qos: .utility)
    private let maxMemoryCount = 1000
    private let maxMemoryLength = 2000
    private weak var currentSession: ConversationSession?

    @Published var memoryCount: Int = 0

    private init() {
        Task {
            await updateMemoryCount()
        }
    }

    func setCurrentSession(_ session: ConversationSession?) {
        currentSession = session
    }

    private func getCurrentConversationId() -> String? {
        currentSession?.id.description
    }

    // MARK: - Public Async API

    func storeAsync(content: String, conversationId: String? = nil) async throws {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw MemoryStoreError.invalidContent("Memory content cannot be empty")
        }

        guard trimmedContent.count <= maxMemoryLength else {
            throw MemoryStoreError.invalidContent("Memory content exceeds maximum length of \(maxMemoryLength) characters")
        }

        let contextId = conversationId ?? getCurrentConversationId()

        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    let memory = Memory(deviceId: Storage.deviceId, content: trimmedContent, conversationId: contextId)
                    try storage.insertMemory(memory)

                    try storage.deleteOldMemories(keepCount: self.maxMemoryCount)

                    Task { @MainActor in
                        await self.updateMemoryCount()
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func getAllMemoriesAsync() async throws -> [Memory] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    let memories = try storage.getAllMemories()
                    continuation.resume(returning: memories)
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func getMemoriesWithLimit(_ limit: Int) async throws -> [Memory] {
        let safeLimit = min(max(limit, 1), 100)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    let memories = try storage.getMemoriesWithLimit(safeLimit)
                    continuation.resume(returning: memories)
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func searchMemories(query: String, limit: Int = 20) async throws -> [Memory] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return try await getAllMemoriesAsync()
        }

        let safeLimit = min(max(limit, 1), 100)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    let memories = try storage.searchMemories(query: trimmedQuery, limit: safeLimit)
                    continuation.resume(returning: memories)
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func updateMemoryAsync(id: String, newContent: String) async throws {
        let trimmedContent = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw MemoryStoreError.invalidContent("Memory content cannot be empty")
        }

        guard trimmedContent.count <= maxMemoryLength else {
            throw MemoryStoreError.invalidContent("Memory content exceeds maximum length of \(maxMemoryLength) characters")
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    let storage = try Storage.db()
                    guard let existingMemory = try storage.getMemory(id: id) else {
                        continuation.resume(throwing: MemoryStoreError.memoryNotFound(id))
                        return
                    }

                    existingMemory.update(\.content, to: trimmedContent)
                    try storage.updateMemory(existingMemory)

                    continuation.resume()
                } catch let error as Storage.MemoryError {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func deleteMemoryAsync(id: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    try storage.deleteMemory(id: id)

                    Task { @MainActor in
                        await self.updateMemoryCount()
                    }

                    continuation.resume()
                } catch let error as Storage.MemoryError {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func deleteAllMemoriesAsync() async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    try storage.deleteAllMemories()

                    Task { @MainActor in
                        await self.updateMemoryCount()
                    }

                    continuation.resume()
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    func getMemoryCount() async throws -> Int {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let storage = try Storage.db()
                    let count = try storage.getMemoryCount()
                    continuation.resume(returning: count)
                } catch {
                    continuation.resume(throwing: MemoryStoreError.storageError(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Sync API

    func getAllMemories() -> String {
        do {
            let memories = try Storage.db().getAllMemories()

            if memories.isEmpty {
                return "No memories stored yet."
            } else {
                var result = "Stored memories:\n\n"
                for (index, memory) in memories.enumerated() {
                    let timestamp = ISO8601DateFormatter().string(from: memory.creation)
                    result += "\(index + 1). [\(timestamp)] \(memory.content)\n"
                }
                return result
            }
        } catch {
            return "Failed to retrieve memories: \(error.localizedDescription)"
        }
    }

    func listMemoriesWithIds(limit: Int = 20) -> String {
        do {
            let storage = try Storage.db()
            let memories = try storage.getMemoriesWithLimit(min(max(limit, 1), 100))

            if memories.isEmpty {
                return "No memories stored yet."
            } else {
                var result = "Stored memories:\n\n"
                for (index, memory) in memories.enumerated() {
                    let timestamp = ISO8601DateFormatter().string(from: memory.creation)
                    result += "\(index + 1). ID: \(memory.id)\n   [\(timestamp)] \(memory.content)\n\n"
                }
                return result
            }
        } catch {
            return "Failed to retrieve memories: \(error.localizedDescription)"
        }
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

            Task { @MainActor in
                await self.updateMemoryCount()
            }

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

    func store(content: String, conversationId: String? = nil) {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty, trimmedContent.count <= maxMemoryLength else {
            Logger.database.errorFile("MemoryStore invalid memory content")
            return
        }

        let contextId = conversationId ?? getCurrentConversationId()

        queue.async {
            do {
                let storage = try Storage.db()
                let memory = Memory(deviceId: Storage.deviceId, content: trimmedContent, conversationId: contextId)
                try storage.insertMemory(memory)
                try storage.deleteOldMemories(keepCount: self.maxMemoryCount)

                Task { @MainActor in
                    await self.updateMemoryCount()
                }
            } catch {
                Logger.database.errorFile("MemoryStore failed to store memory: \(error)")
            }
        }
    }

    func formattedProactiveMemoryContext() async -> String? {
        await formattedProactiveMemoryContext(for: MemoryProactiveProvisionSetting.currentScope)
    }

    func formattedProactiveMemoryContext(for scope: MemoryProactiveProvisionScope) async -> String? {
        switch scope.filter {
        case .none:
            return nil
        default:
            break
        }

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
            let note = String(localized: "This summary is provided automatically according to the user's proactive memory setting, even when memory tools are disabled.")

            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .medium
            dateFormatter.timeStyle = .short

            let body = filteredMemories.enumerated().map { index, memory -> String in
                let timestamp = dateFormatter.string(from: memory.creation)
                return String(localized: "\(index + 1). [\(timestamp)] \(memory.content)")
            }
            .joined(separator: "\n")

            return [header, scopeLine, note, "", body].joined(separator: "\n")
        } catch {
            Logger.database.errorFile("MemoryStore failed to build proactive memory context: \(error)")
            return nil
        }
    }

    private func updateMemoryCount() async {
        do {
            let count = try await getMemoryCount()
            memoryCount = count
        } catch {
            Logger.database.errorFile("MemoryStore failed to update memory count: \(error)")
        }
    }
}

// MARK: - Error Types

public enum MemoryStoreError: Error, LocalizedError {
    case invalidContent(String)
    case memoryNotFound(String)
    case storageError(String)
    case quotaExceeded(String)

    var localizedDescription: String {
        switch self {
        case let .invalidContent(message):
            "Invalid content: \(message)"
        case let .memoryNotFound(id):
            "Memory not found: \(id)"
        case let .storageError(message):
            "Storage error: \(message)"
        case let .quotaExceeded(message):
            "Quota exceeded: \(message)"
        }
    }
}

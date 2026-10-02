@testable import FlowDown
import Foundation
import Testing

/// Settings alerts and the tool row read `error.localizedDescription` from an
/// `any Error`, which bridges through `LocalizedError.errorDescription`. Every
/// input here is rejected or misses, so no memory rows are written.
struct MemoryStoreErrorTests {
    @Test
    func memoryStoreError_erasedToAnyError_reportsLocalizedReason() {
        let reason = "disk full"
        let id = "missing-id"

        #expect(
            erasedDescription(.invalidContent(reason))
                == String(localized: "Invalid content: \(reason)"),
        )
        #expect(
            erasedDescription(.memoryNotFound(id))
                == String(localized: "Memory not found: \(id)"),
        )
        #expect(
            erasedDescription(.storageError(reason))
                == String(localized: "Storage error: \(reason)"),
        )
    }

    @Test
    @MainActor
    func memoryStoreError_storeEmptyContent_reportsLocalizedReason() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let error = await #expect(throws: MemoryStoreError.self) {
            _ = try await MemoryStore.shared.storeAsync(content: "   ")
        }
        let reason = String(localized: "Memory content cannot be empty")
        #expect(erasedDescription(error) == String(localized: "Invalid content: \(reason)"))
    }

    @Test
    @MainActor
    func memoryStoreError_storeOverlongContent_reportsLocalizedReason() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let maxLength = 2000
        let error = await #expect(throws: MemoryStoreError.self) {
            _ = try await MemoryStore.shared.storeAsync(
                content: String(repeating: "a", count: maxLength + 1),
            )
        }
        let reason = String(localized: "Memory content exceeds maximum length of \(maxLength) characters")
        #expect(erasedDescription(error) == String(localized: "Invalid content: \(reason)"))
    }

    @Test
    @MainActor
    func memoryStoreError_updateUnknownMemory_reportsLocalizedReason() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let id = UUID().uuidString
        let error = await #expect(throws: MemoryStoreError.self) {
            try await MemoryStore.shared.updateMemoryAsync(id: id, newContent: "User likes tea")
        }
        #expect(erasedDescription(error) == String(localized: "Memory not found: \(id)"))
    }
}

private extension MemoryStoreErrorTests {
    /// Reads the description the way a `catch` block does, through `any Error`.
    func erasedDescription(_ error: MemoryStoreError?) -> String? {
        guard let error else { return nil }
        let erased: any Error = error
        return erased.localizedDescription
    }
}

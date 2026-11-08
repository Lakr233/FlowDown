@testable import FlowDown
import Foundation
import Storage
import Testing

/// Every input here is rejected before it reaches the database, so these
/// tests never write rows that the serialized memory suites could observe.
struct StoreMemoryToolTests {
    @Test
    @MainActor
    func storeMemory_emptyContent_throwsInvalidContent() async throws {
        try await expectRejected(#"{"content":""}"#)
    }

    @Test
    @MainActor
    func storeMemory_whitespaceContent_throwsInvalidContent() async throws {
        try await expectRejected(#"{"content":"   "}"#)
    }

    @Test
    @MainActor
    func storeMemory_overlongContent_throwsInvalidContent() async throws {
        let content = String(repeating: "a", count: 2001)
        try await expectRejected(#"{"content":"\#(content)"}"#)

        let memories = try await MemoryStore.shared.getAllMemoriesAsync()
        #expect(!memories.contains { $0.content == content })
    }
}

private extension StoreMemoryToolTests {
    @MainActor
    func expectRejected(_ input: String) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let error = await #expect(throws: NSError.self) {
            try await MTStoreMemoryTool().execute(.init(json: input), context: .headless)
        }
        #expect(error?.code == 400)
        // The pipeline reports `error.localizedDescription` to the model and the
        // tool row, so it must be the localized rejection message.
        #expect(error?.localizedDescription == String(localized: "Invalid memory content"))
    }
}

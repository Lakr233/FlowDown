import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

/// Chat Completions providers such as Ollama send `"content": ""` beside every
/// reasoning delta, so the stream alternates reasoning with empty text. An
/// empty text chunk must not make the producer wait for the paced reasoning
/// emitter to drain, or the stream crawls at about 30 characters a second.
struct ModelManagerStreamingEmptyChunkTests {
    private static let deltaCount = 300
    private static let reasoningDelta = "abcd"

    @Test
    func streamingInfer_emptyTextBetweenReasoningDeltas_doesNotPaceTheStream() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerStreamingEmptyChunkTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // An isolated manager, so the injected factory never races other
        // suites that swap the shared one.
        let manager = ModelManager(
            localModelDir: root.appendingPathComponent("Models.Local", isDirectory: true),
            localModelDownloadTempDir: root.appendingPathComponent("Models.Local.Temp", isDirectory: true),
        )

        var chunks: [ChatResponseChunk] = []
        for _ in 0 ..< Self.deltaCount {
            chunks.append(.reasoning(Self.reasoningDelta))
            chunks.append(.text(""))
        }
        chunks.append(.text("done"))
        let service = ChatServiceSpy()
        service.streamHandler = { [chunks] _ in
            AnyAsyncSequence(makeResponseStream(chunks))
        }
        manager.chatServiceFactory = { _, _ in service }

        let clock = ContinuousClock()
        let start = clock.now
        let stream = try await manager.streamingInfer(
            with: "unit-test-model",
            input: [.user(content: .text("Ping"))],
        )

        var reasoning = ""
        var text = ""
        for try await chunk in stream {
            switch chunk {
            case let .reasoning(value): reasoning += value
            case let .text(value): text += value
            default: break
            }
        }
        let elapsed = clock.now - start

        #expect(reasoning == String(repeating: Self.reasoningDelta, count: Self.deltaCount))
        #expect(text == "done")
        // Paced one character per step, the 1,200 reasoning characters took
        // about 40 seconds; drained in proportional batches they take about one.
        #expect(elapsed < .seconds(3), "streaming took \(elapsed)")
    }
}

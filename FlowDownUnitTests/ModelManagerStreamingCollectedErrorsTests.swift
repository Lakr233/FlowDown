import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct ModelManagerStreamingCollectedErrorsTests {
    private static let partialText = "Partial rewrite"
    private static let droppedConnection = "The network connection was lost."

    @Test
    func streamingInferDropAfterText_throwsWhenFailingOnCollectedErrors() async throws {
        let outcome = try await consumeDroppedStream(failsOnCollectedErrors: true)

        #expect(outcome.text == Self.partialText)
        #expect(outcome.error?.localizedDescription == Self.droppedConnection)
    }

    @Test
    func streamingInferDropAfterText_keepsPartialOutputByDefault() async throws {
        let outcome = try await consumeDroppedStream(failsOnCollectedErrors: false)

        #expect(outcome.text == Self.partialText)
        #expect(outcome.error == nil)
    }

    /// Streams partial text from a client that then records a dropped
    /// connection and still finishes normally, as the remote clients do.
    private func consumeDroppedStream(
        failsOnCollectedErrors: Bool,
    ) async throws -> (text: String, error: (any Error)?) {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerStreamingCollectedErrorsTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // An isolated manager, so the injected factory never races other
        // suites that swap the shared one.
        let manager = ModelManager(
            localModelDir: root.appendingPathComponent("Models.Local", isDirectory: true),
            localModelDownloadTempDir: root.appendingPathComponent("Models.Local.Temp", isDirectory: true),
        )

        let service = ChatServiceSpy()
        let collector = service.errorCollector
        service.streamHandler = { _ in
            AnyAsyncSequence(
                AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                    Task {
                        continuation.yield(.text(Self.partialText))
                        await collector.collect(Self.droppedConnection)
                        continuation.finish()
                    }
                },
            )
        }
        manager.chatServiceFactory = { _, _ in service }

        let stream = try await manager.streamingInfer(
            with: "unit-test-model",
            input: [.user(content: .text("Ping"))],
            failsOnCollectedErrors: failsOnCollectedErrors,
        )

        var text = ""
        do {
            for try await chunk in stream {
                if case let .text(value) = chunk {
                    text += value
                }
            }
        } catch {
            return (text, error)
        }
        return (text, nil)
    }
}

import ChatClientKit
@testable import FlowDown
import Foundation
import os
import Testing

struct ModelManagerStreamingCancellationTests {
    @Test
    func streamingInferStop_cancelsUnderlyingModelStream() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerStreamingCancellationTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // An isolated manager, so the injected factory never races other
        // suites that swap the shared one.
        let manager = ModelManager(
            localModelDir: root.appendingPathComponent("Models.Local", isDirectory: true),
            localModelDownloadTempDir: root.appendingPathComponent("Models.Local.Temp", isDirectory: true),
        )

        let probe = UpstreamProbe()
        let service = ChatServiceSpy(streamHandler: { _ in
            AnyAsyncSequence(
                AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                    continuation.onTermination = { reason in
                        if case .cancelled = reason { probe.markCancelled() }
                    }
                    // A model that keeps generating until someone stops it.
                    continuation.yield(.text("Hello"))
                },
            )
        })
        manager.chatServiceFactory = { _, _ in service }

        let stream = try await manager.streamingInfer(
            with: "unit-test-model",
            input: [.user(content: .text("Ping"))],
        )
        let consumer = Task {
            for try await _ in stream {
                probe.markReceived()
            }
        }

        #expect(await eventually { probe.received })
        consumer.cancel()

        #expect(await eventually { probe.cancelled })
    }
}

private final class UpstreamProbe: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (received: false, cancelled: false))

    var received: Bool { state.withLock { $0.received } }
    var cancelled: Bool { state.withLock { $0.cancelled } }

    func markReceived() {
        state.withLock { $0.received = true }
    }

    func markCancelled() {
        state.withLock { $0.cancelled = true }
    }
}

private func eventually(
    deadline: Duration = .seconds(10),
    _ condition: @escaping () async -> Bool,
) async -> Bool {
    let clock = ContinuousClock()
    let start = clock.now
    while clock.now - start < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return await condition()
}

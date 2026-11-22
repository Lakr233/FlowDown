@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

/// The in-app log must show every stage of a cloud request, so an empty
/// reply always leaves a trace.
struct PrivateCloudComputeRequestLogTests {
    final class Lines: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [(PrivateCloudComputeRequestLog.Level, String)] = []

        func append(_ level: PrivateCloudComputeRequestLog.Level, _ line: String) {
            lock.withLock { storage.append((level, line)) }
        }

        var all: [(PrivateCloudComputeRequestLog.Level, String)] {
            lock.withLock { storage }
        }

        var errors: [String] {
            all.filter { $0.0 == .error }.map(\.1)
        }

        func contains(_ text: String) -> Bool {
            all.contains { $0.1.contains(text) }
        }
    }

    struct SampleError: LocalizedError {
        var errorDescription: String? {
            "sample failure"
        }
    }

    private func makeService(
        _ stream: @escaping @Sendable (ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk>,
    ) -> (PrivateCloudComputeLoggingChatService, Lines) {
        let lines = Lines()
        let log = PrivateCloudComputeRequestLog(id: "test") { lines.append($0, $1) }
        let inner = ChatServiceSpy(streamHandler: stream)
        return (PrivateCloudComputeLoggingChatService(inner: inner, log: log), lines)
    }

    private func collect(_ service: any ChatService) async throws -> [ChatResponseChunk] {
        var chunks: [ChatResponseChunk] = []
        for try await chunk in try await service.streamingChat(body: ChatRequestBody(messages: [.user(content: .text("你好"))])) {
            chunks.append(chunk)
        }
        return chunks
    }

    @Test
    func `a reply passes through and the log has start, first chunk and finish`() async throws {
        let (service, lines) = makeService { _ in
            AnyAsyncSequence(makeResponseStream([.reasoning("hm"), .text("你好"), .text("！")]))
        }
        let chunks = try await collect(service)

        #expect(chunks == [.reasoning("hm"), .text("你好"), .text("！")])
        #expect(lines.contains("[PCC test] request start"))
        #expect(lines.contains("entitlement="))
        #expect(lines.contains("availability="))
        #expect(lines.contains("first chunk (reasoning)"))
        #expect(lines.contains("request finished after"))
        #expect(lines.contains("textChunks=2 (3 chars)"))
        #expect(lines.errors.isEmpty)
    }

    @Test
    func `an empty reply is logged as an error`() async throws {
        let (service, lines) = makeService { _ in
            AnyAsyncSequence(makeResponseStream([]))
        }
        let chunks = try await collect(service)

        #expect(chunks.isEmpty)
        #expect(lines.errors.contains { $0.contains("finished without any output") })
    }

    @Test
    func `an error in the stream is logged and still thrown`() async {
        let (service, lines) = makeService { _ in
            AnyAsyncSequence(AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                continuation.yield(.text("partial"))
                continuation.finish(throwing: SampleError())
            })
        }

        await #expect(throws: SampleError.self) {
            _ = try await collect(service)
        }
        #expect(lines.errors.contains { $0.contains("request failed after") && $0.contains("SampleError") })
        #expect(lines.errors.contains { $0.contains("sample failure") })
    }

    @Test
    func `an error before streaming is logged and still thrown`() async {
        let (service, lines) = makeService { _ in throw SampleError() }

        await #expect(throws: SampleError.self) {
            _ = try await collect(service)
        }
        #expect(lines.errors.contains { $0.contains("request failed before streaming") })
    }

    @Test
    func `an unavailable error is described with its mapped failure`() {
        let description = PrivateCloudComputeRequestLog.describe(
            PrivateCloudComputeUnavailableError(reason: .systemNotReady),
        )
        #expect(description.contains("PrivateCloudComputeUnavailableError"))
        #expect(description.contains("mapped=unavailable"))
    }

    @Test
    func `framework events are written with the failure in full`() {
        let lines = Lines()
        let log = PrivateCloudComputeRequestLog(id: "ev") { lines.append($0, $1) }

        log.record(.sessionCreated(historyEntries: 0, tools: 0, instructionsLength: 12, promptLength: 2, reasoningDepth: .deep))
        log.record(.requestSent)
        log.record(.snapshot(index: 1, contentLength: 2, reasoningLength: 0, transcriptEntries: 3))
        log.record(.snapshot(index: 2, contentLength: 3, reasoningLength: 0, transcriptEntries: 3))
        log.record(.finished(snapshots: 2, contentLength: 3, reasoningLength: 0))
        log.record(.failed(snapshots: 0, error: SampleError()))

        #expect(lines.contains("[PCC ev] session created: history=0 tools=0 instructionsChars=12 promptChars=2 reasoning=deep"))
        #expect(lines.contains("streamResponse called"))
        #expect(lines.contains("snapshot #1"))
        #expect(!lines.contains("snapshot #2"))
        #expect(lines.contains("framework stream finished: snapshots=2"))
        #expect(lines.errors.contains { $0.contains("framework stream threw after 0 snapshots") && $0.contains("sample failure") })
    }
}

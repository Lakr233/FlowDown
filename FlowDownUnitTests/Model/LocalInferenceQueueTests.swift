import ChatClientKit
@testable import FlowDown
import Foundation
import os
import Testing

struct LocalInferenceQueueTests {
    @Test
    func `concurrent requests run one at a time`() async throws {
        let queue = LocalInferenceQueue(offload: {})
        let recorder = ConcurrencyRecorder()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0 ..< 8 {
                group.addTask {
                    try await queue.run {
                        recorder.enter()
                        try await Task.sleep(for: .milliseconds(20))
                        recorder.leave()
                    }
                }
            }
            try await group.waitForAll()
        }

        #expect(recorder.maxActive == 1)
        #expect(recorder.completed == 8)
        #expect(await queue.isBusy == false)
    }

    @Test
    func `requests are served in arrival order`() async throws {
        let queue = LocalInferenceQueue(offload: {})
        let recorder = OrderRecorder()
        let holder = try await queue.acquire()

        var tasks: [Task<Void, Error>] = []
        for index in 0 ..< 4 {
            tasks.append(Task {
                try await queue.run { recorder.append("\(index)") }
            })
            #expect(await eventually { await queue.waitingCount == index + 1 })
        }

        await queue.release(holder)
        for task in tasks {
            try await task.value
        }
        #expect(recorder.events == ["0", "1", "2", "3"])
    }

    @Test
    func `cancelling a waiting request does not block the next one`() async throws {
        let queue = LocalInferenceQueue(offload: {})
        let holder = try await queue.acquire()

        let cancelled = Task { try await queue.acquire() }
        #expect(await eventually { await queue.waitingCount == 1 })
        let next = Task { try await queue.acquire() }
        #expect(await eventually { await queue.waitingCount == 2 })

        cancelled.cancel()
        await #expect(throws: CancellationError.self) {
            _ = try await cancelled.value
        }
        #expect(await eventually { await queue.waitingCount == 1 })

        await queue.release(holder)
        let permit = try await next.value
        #expect(await queue.isBusy)
        await queue.release(permit)
        #expect(await queue.isBusy == false)
    }

    @Test
    func `an already cancelled request never takes the queue`() async throws {
        let queue = LocalInferenceQueue(offload: {})
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await queue.acquire()
        }
        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await queue.isBusy == false)
        let permit = try await queue.acquire()
        await queue.release(permit)
    }

    @Test
    func `a failing request releases the queue`() async throws {
        let queue = LocalInferenceQueue(offload: {})
        await #expect(throws: CancellationError.self) {
            try await queue.run { throw CancellationError() }
        }
        #expect(await queue.isBusy == false)
        let permit = try await queue.acquire()
        await queue.release(permit)
    }

    @Test
    func `memory pressure offload waits for the running generation`() async throws {
        let recorder = OrderRecorder()
        let queue = LocalInferenceQueue(offload: { recorder.append("offload") })

        let generation = try await queue.acquire()
        await queue.requestOffload()
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.events.isEmpty)
        #expect(await queue.hasPendingOffload)

        recorder.append("generation finished")
        await queue.release(generation)

        #expect(await eventually { recorder.events.count == 2 })
        #expect(recorder.events == ["generation finished", "offload"])
        #expect(await eventually { await queue.isBusy == false })
    }

    @Test
    func `memory pressure offload runs at once when idle`() async {
        let recorder = OrderRecorder()
        let queue = LocalInferenceQueue(offload: { recorder.append("offload") })

        await queue.requestOffload()

        #expect(await eventually { recorder.events == ["offload"] })
        #expect(await queue.hasPendingOffload == false)
    }

    @Test
    func `deferred offload runs before the next waiting request`() async throws {
        let recorder = OrderRecorder()
        let queue = LocalInferenceQueue(offload: {
            try? await Task.sleep(for: .milliseconds(50))
            recorder.append("offload")
        })

        let first = try await queue.acquire()
        let second = Task {
            try await queue.run { recorder.append("second") }
        }
        #expect(await eventually { await queue.waitingCount == 1 })
        await queue.requestOffload()

        await queue.release(first)
        try await second.value

        #expect(recorder.events == ["offload", "second"])
    }

    @Test
    func `a request arriving during an offload waits for it`() async throws {
        let recorder = OrderRecorder()
        let gate = AsyncGate()
        let queue = LocalInferenceQueue(offload: {
            await gate.wait()
            recorder.append("offload")
        })

        await queue.requestOffload()
        let request = Task {
            try await queue.run { recorder.append("request") }
        }
        #expect(await eventually { await queue.waitingCount == 1 })
        #expect(recorder.events.isEmpty)

        await gate.open()
        try await request.value
        #expect(recorder.events == ["offload", "request"])
    }
}

@Suite(.serialized)
struct ModelManagerOnDeviceQueueTests {
    @Test
    func `concurrent on-device streams are serialized`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let (manager, root) = makeIsolatedManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = ConcurrencyRecorder()
        let service = ChatServiceSpy(streamHandler: { _ in
            recorder.enter()
            return AnyAsyncSequence(
                AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                    let task = Task {
                        continuation.yield(.text("Hello"))
                        try? await Task.sleep(for: .milliseconds(80))
                        recorder.leave()
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                },
            )
        })
        manager.chatServiceFactory = { _, _ in service }
        manager.onDeviceModelPredicate = { _ in true }

        try await withThrowingTaskGroup(of: String.self) { group in
            for _ in 0 ..< 3 {
                group.addTask {
                    let stream = try await manager.streamingInfer(
                        with: "on-device-model",
                        input: [.user(content: .text("Ping"))],
                    )
                    var text = ""
                    for try await chunk in stream {
                        if case let .text(value) = chunk { text += value }
                    }
                    return text
                }
            }
            for try await text in group {
                #expect(text == "Hello")
            }
        }

        #expect(recorder.maxActive == 1)
        #expect(recorder.completed == 3)
    }

    @Test
    func `cancelling an on-device stream frees the queue for the next request`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let (manager, root) = makeIsolatedManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let endless = ChatServiceSpy(streamHandler: { _ in
            AnyAsyncSequence(
                AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                    // A model that keeps generating until someone stops it.
                    continuation.yield(.text("Still going"))
                },
            )
        })
        let finite = ChatServiceSpy(streamHandler: { _ in
            AnyAsyncSequence(makeResponseStream([.text("Done")]))
        })
        manager.chatServiceFactory = { identifier, _ in
            identifier == "endless" ? endless : finite
        }
        manager.onDeviceModelPredicate = { _ in true }

        let first = try await manager.streamingInfer(
            with: "endless",
            input: [.user(content: .text("Ping"))],
        )
        let received = OrderRecorder()
        let consumer = Task {
            for try await _ in first {
                received.append("chunk")
            }
        }
        #expect(await eventually { !received.events.isEmpty })
        #expect(await manager.localInferenceQueue.isBusy)

        consumer.cancel()

        let second = Task {
            var text = ""
            let stream = try await manager.streamingInfer(
                with: "finite",
                input: [.user(content: .text("Ping"))],
            )
            for try await chunk in stream {
                if case let .text(value) = chunk { text += value }
            }
            return text
        }
        let text = try await withTimeout(.seconds(10)) { try await second.value }
        #expect(text == "Done")
        #expect(await eventually { await manager.localInferenceQueue.isBusy == false })
    }

    @Test
    func `memory pressure during an on-device stream is deferred until it ends`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let (manager, root) = makeIsolatedManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let recorder = OrderRecorder()
        manager.localInferenceQueue = LocalInferenceQueue(offload: { recorder.append("offload") })
        let finishGeneration = AsyncGate()
        let service = ChatServiceSpy(streamHandler: { _ in
            AnyAsyncSequence(
                AsyncThrowingStream<ChatResponseChunk, Error> { continuation in
                    let task = Task {
                        continuation.yield(.text("Hello"))
                        await finishGeneration.wait()
                        recorder.append("generation finished")
                        continuation.finish()
                    }
                    continuation.onTermination = { _ in task.cancel() }
                },
            )
        })
        manager.chatServiceFactory = { _, _ in service }
        manager.onDeviceModelPredicate = { _ in true }

        let stream = try await manager.streamingInfer(
            with: "on-device-model",
            input: [.user(content: .text("Ping"))],
        )
        let consumer = Task {
            for try await _ in stream {}
        }
        #expect(await eventually { await manager.localInferenceQueue.isBusy })

        await manager.localInferenceQueue.requestOffload()
        try await Task.sleep(for: .milliseconds(100))
        #expect(recorder.events.isEmpty)

        await finishGeneration.open()
        try await consumer.value

        #expect(await eventually { recorder.events.count == 2 })
        #expect(recorder.events == ["generation finished", "offload"])
    }

    @Test
    func `remote models do not wait for the on-device queue`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let (manager, root) = makeIsolatedManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ChatServiceSpy(chatHandler: { _ in
            ChatResponse(reasoning: "", text: "Remote", images: [], tools: [])
        })
        manager.chatServiceFactory = { _, _ in service }

        let holder = try await manager.localInferenceQueue.acquire()
        let response = try await withTimeout(.seconds(10)) {
            try await manager.infer(with: "remote-model", input: [.user(content: .text("Ping"))])
        }
        #expect(response.text == "Remote")
        await manager.localInferenceQueue.release(holder)
    }

    @Test
    func `on-device buffered inference waits for its turn`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let (manager, root) = makeIsolatedManager()
        defer { try? FileManager.default.removeItem(at: root) }

        let service = ChatServiceSpy(chatHandler: { _ in
            ChatResponse(reasoning: "", text: "Local", images: [], tools: [])
        })
        manager.chatServiceFactory = { _, _ in service }
        manager.onDeviceModelPredicate = { _ in true }

        let holder = try await manager.localInferenceQueue.acquire()
        let request = Task {
            try await manager.infer(with: "on-device-model", input: [.user(content: .text("Ping"))])
        }
        #expect(await eventually { await manager.localInferenceQueue.waitingCount == 1 })
        #expect(service.receivedBodies.isEmpty)

        await manager.localInferenceQueue.release(holder)
        let response = try await request.value
        #expect(response.text == "Local")
        #expect(await manager.localInferenceQueue.isBusy == false)
    }

    private func makeIsolatedManager() -> (ModelManager, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerOnDeviceQueueTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let manager = ModelManager(
            localModelDir: root.appendingPathComponent("Models.Local", isDirectory: true),
            localModelDownloadTempDir: root.appendingPathComponent("Models.Local.Temp", isDirectory: true),
        )
        // Never the shared queue, so these tests can't hold up other suites.
        manager.localInferenceQueue = LocalInferenceQueue(offload: {})
        return (manager, root)
    }
}

private final class ConcurrencyRecorder: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: (active: 0, maxActive: 0, completed: 0))

    var maxActive: Int { state.withLock { $0.maxActive } }
    var completed: Int { state.withLock { $0.completed } }

    func enter() {
        state.withLock {
            $0.active += 1
            $0.maxActive = max($0.maxActive, $0.active)
        }
    }

    func leave() {
        state.withLock {
            $0.active -= 1
            $0.completed += 1
        }
    }
}

private final class OrderRecorder: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [String]())

    var events: [String] { state.withLock { $0 } }

    func append(_ event: String) {
        state.withLock { $0.append(event) }
    }
}

/// A one-shot latch: `wait()` suspends until `open()` is called.
private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }
}

private struct TimeoutError: Error {}

private func withTimeout<T: Sendable>(
    _ duration: Duration,
    _ operation: @escaping @Sendable () async throws -> T,
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
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
        try? await Task.sleep(for: .milliseconds(20))
    }
    return await condition()
}

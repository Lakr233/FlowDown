@testable import FlowDown
import Foundation
import os
import Testing

struct AwaitCancellableTests {
    @Test
    func `normal completion returns the value without abandoning`() async throws {
        let abandonCount = OSAllocatedUnfairLock(initialState: 0)
        let value = try await awaitCancellable {
            42
        } onAbandon: {
            abandonCount.withLock { $0 += 1 }
        }
        #expect(value == 42)
        #expect(abandonCount.withLock { $0 } == 0)
    }

    @Test
    func `cancellation mid-wait resumes immediately and abandons once`() async throws {
        let abandonCount = OSAllocatedUnfairLock(initialState: 0)
        let task = Task { () -> Error? in
            do {
                _ = try await awaitCancellable {
                    try await Task.sleep(for: .seconds(60))
                    return 1
                } onAbandon: {
                    abandonCount.withLock { $0 += 1 }
                }
                return nil
            } catch {
                return error
            }
        }
        try await Task.sleep(for: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        task.cancel()
        let error = await task.value
        #expect(clock.now - start < .seconds(5))
        #expect(error is CancellationError)
        #expect(abandonCount.withLock { $0 } == 1)
    }

    @Test
    func `task cancelled before the wait starts still throws and abandons once`() async {
        let abandonCount = OSAllocatedUnfairLock(initialState: 0)
        let operationRan = OSAllocatedUnfairLock(initialState: false)
        let task = Task { () -> Error? in
            // Spin until our own cancellation is visible, so awaitCancellable
            // is entered by an already-cancelled task.
            while !Task.isCancelled { await Task.yield() }
            do {
                _ = try await awaitCancellable {
                    operationRan.withLock { $0 = true }
                    return 1
                } onAbandon: {
                    abandonCount.withLock { $0 += 1 }
                }
                return nil
            } catch {
                return error
            }
        }
        task.cancel()
        let error = await task.value
        #expect(error is CancellationError)
        #expect(abandonCount.withLock { $0 } == 1)
        #expect(operationRan.withLock { $0 } == false)
    }

    @Test
    func `timeout abandons the wait with timedOut`() async {
        let abandonCount = OSAllocatedUnfairLock(initialState: 0)
        let clock = ContinuousClock()
        let start = clock.now
        do {
            _ = try await awaitCancellable(timeout: .milliseconds(100)) {
                try await Task.sleep(for: .seconds(60))
                return 1
            } onAbandon: {
                abandonCount.withLock { $0 += 1 }
            }
            Issue.record("Expected timeout to throw.")
        } catch {
            #expect(error is AwaitCancellableError)
        }
        #expect(clock.now - start < .seconds(10))
        #expect(abandonCount.withLock { $0 } == 1)
    }

    @Test
    func `late result after abandon is discarded`() async throws {
        let waiter = CancellableWaiter<Int>()
        let task = Task { try await waiter.value() }
        try await Task.sleep(for: .milliseconds(50))
        waiter.abandon(throwing: CancellationError())
        #expect(waiter.complete(with: .success(7)) == false)
        do {
            _ = try await task.value
            Issue.record("Expected abandoned wait to throw.")
        } catch {
            #expect(error is CancellationError)
        }
    }

    @Test
    func `racing complete and abandon resumes exactly once`() async {
        // A double resume of a CheckedContinuation traps, so surviving the
        // loop is the assertion.
        for _ in 0 ..< 200 {
            let waiter = CancellableWaiter<Int>()
            let awaiting = Task { try? await waiter.value() }
            let completer = Task { waiter.complete(with: .success(1)) }
            let abandoner = Task { waiter.abandon(throwing: CancellationError()) }
            _ = await completer.value
            _ = await abandoner.value
            _ = await awaiting.value
        }
    }

    @Test
    func `result arriving before the wait is delivered`() async throws {
        let waiter = CancellableWaiter<Int>()
        #expect(waiter.complete(with: .success(9)) == true)
        let value = try await waiter.value()
        #expect(value == 9)
    }
}

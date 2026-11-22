//
//  LocalInferenceQueue.swift
//  FlowDown
//

import Foundation
import MLX

/// The single serial path for on-device inference (MLX and the Apple
/// Foundation Model).
///
/// One request holds the queue at a time, from model load until its output
/// stream ends. Others wait in FIFO order without blocking a thread: waiting
/// is an `await` on a continuation, never a semaphore or a lock. A waiter that
/// is cancelled leaves the line at once with `CancellationError`, so it can
/// never hold up the requests behind it.
///
/// Memory-pressure offloads go through the same queue. When the queue is idle
/// the offload runs at once; while a generation holds it, the offload waits
/// and runs as soon as that generation releases, before the next one starts.
actor LocalInferenceQueue {
    struct Permit: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    typealias Offload = @Sendable () async -> Void

    static let shared = LocalInferenceQueue {
        await MLX.GPU.offloadRuntimeResources()
    }

    private struct Waiter {
        let permit: Permit
        let continuation: CheckedContinuation<Void, Error>
    }

    private let offload: Offload
    private var holder: Permit?
    private var waiters: [Waiter] = []
    private var isOffloading = false
    private var isOffloadPending = false

    init(offload: @escaping Offload) {
        self.offload = offload
    }

    /// Whether a request currently holds the queue.
    var isBusy: Bool { holder != nil }
    /// Whether an offload is waiting for the running request to finish.
    var hasPendingOffload: Bool { isOffloadPending }
    var waitingCount: Int { waiters.count }

    /// Waits for this request's turn. Throws `CancellationError` if the task
    /// is cancelled before its turn comes; nothing is held in that case.
    func acquire() async throws -> Permit {
        try Task.checkCancellation()
        let permit = Permit()
        if holder == nil, waiters.isEmpty, !isOffloading, !isOffloadPending {
            holder = permit
            return permit
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                waiters.append(Waiter(permit: permit, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(permit) }
        }
        return permit
    }

    /// Ends the turn of `permit` and hands the queue to the next request.
    /// Releasing a permit that does not hold the queue does nothing.
    func release(_ permit: Permit) {
        guard holder == permit else { return }
        holder = nil
        advance()
    }

    /// Runs `operation` while holding the queue, releasing it on every exit.
    nonisolated func run<T>(_ operation: () async throws -> T) async throws -> T {
        let permit = try await acquire()
        do {
            let value = try await operation()
            await release(permit)
            return value
        } catch {
            await release(permit)
            throw error
        }
    }

    /// Asks to free cached on-device resources. Runs now when idle, otherwise
    /// right after the running request ends.
    func requestOffload() {
        isOffloadPending = true
        advance()
    }

    private func cancelWaiter(_ permit: Permit) {
        guard let index = waiters.firstIndex(where: { $0.permit == permit }) else { return }
        let waiter = waiters.remove(at: index)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func advance() {
        guard holder == nil, !isOffloading else { return }
        if isOffloadPending {
            isOffloadPending = false
            isOffloading = true
            Task { await self.performOffload() }
            return
        }
        guard !waiters.isEmpty else { return }
        let next = waiters.removeFirst()
        holder = next.permit
        next.continuation.resume()
    }

    private func performOffload() async {
        await offload()
        isOffloading = false
        advance()
    }
}

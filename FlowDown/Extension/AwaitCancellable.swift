//
//  AwaitCancellable.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/11/26.
//

import Foundation
import os

enum AwaitCancellableError: Error, LocalizedError {
    case timedOut

    var errorDescription: String? {
        String(localized: "Operation timed out.")
    }
}

/// Awaits `operation`, but stops waiting the moment the surrounding task is
/// cancelled or `timeout` elapses. The operation itself is not cancelled: it
/// keeps running in the background and its late result is discarded. This is
/// the only way to bound waits on APIs that do not honor cooperative
/// cancellation, such as MCP transports blocked on a dead network.
///
/// `onAbandon` fires exactly once, at the transition that gives up the wait —
/// cancellation or timeout — whether or not the wait was registered yet. A
/// wait that was cancelled before it started still reports the abandon, so
/// callers can notify a server about a request they will never consume.
func awaitCancellable<T: Sendable>(
    timeout: Duration? = nil,
    _ operation: @escaping @Sendable () async throws -> T,
    onAbandon: (@Sendable () -> Void)? = nil,
) async throws -> T {
    if Task.isCancelled {
        onAbandon?()
        throw CancellationError()
    }
    let waiter = CancellableWaiter<T>()
    let timeoutTask: Task<Void, Never>? = timeout.map { timeout in
        Task {
            try? await Task.sleep(for: timeout)
            guard !Task.isCancelled else { return }
            waiter.abandon(throwing: AwaitCancellableError.timedOut)
        }
    }
    Task {
        defer { timeoutTask?.cancel() }
        do {
            let value = try await operation()
            waiter.complete(with: .success(value))
        } catch {
            waiter.complete(with: .failure(error))
        }
    }
    return try await waiter.value(onAbandon: onAbandon)
}

/// A single-use bridge between one awaiting task and callbacks that settle it.
///
/// Guarantees, whatever order the calls arrive in:
/// - the waiter resumes exactly once;
/// - `abandon` beats a not-yet-consumed result, and works before `value()` was
///   even called (the abandon is remembered and delivered on registration);
/// - the `onAbandon` handler runs exactly once per abandoned wait, never for a
///   completed one.
///
/// Task cancellation of the awaiting task counts as an abandon.
final class CancellableWaiter<T: Sendable>: @unchecked Sendable {
    private let state = OSAllocatedUnfairLock(initialState: State.idle)

    private enum State {
        case idle
        /// Completed before anyone awaited; the result waits for `value()`.
        case pendingResult(Result<T, Error>)
        case waiting(CheckedContinuation<T, Error>, onAbandon: (@Sendable () -> Void)?)
        /// Abandoned before anyone awaited; `value()` reports it on arrival.
        case abandonedBeforeWait(Error)
        case finished
    }

    private enum Registration {
        case waiting
        case resume(Result<T, Error>)
        case resumeAbandoned(Error)
    }

    /// Awaits the settled value. May be called at most once.
    func value(onAbandon: (@Sendable () -> Void)? = nil) async throws -> T {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
                let registration: Registration = state.withLock { current in
                    switch current {
                    case .idle:
                        current = .waiting(continuation, onAbandon: onAbandon)
                        return .waiting
                    case let .pendingResult(result):
                        current = .finished
                        return .resume(result)
                    case let .abandonedBeforeWait(error):
                        current = .finished
                        return .resumeAbandoned(error)
                    case .waiting, .finished:
                        assertionFailure("CancellableWaiter awaited twice")
                        return .resumeAbandoned(CancellationError())
                    }
                }
                switch registration {
                case .waiting:
                    break
                case let .resume(result):
                    continuation.resume(with: result)
                case let .resumeAbandoned(error):
                    onAbandon?()
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            abandon(throwing: CancellationError())
        }
    }

    /// Settles the wait with a result. Returns false when the wait was already
    /// settled or abandoned — the caller's result is discarded.
    @discardableResult
    func complete(with result: Result<T, Error>) -> Bool {
        let (continuation, accepted): (CheckedContinuation<T, Error>?, Bool) = state.withLock { current in
            switch current {
            case .idle:
                current = .pendingResult(result)
                return (nil, true)
            case let .waiting(continuation, _):
                current = .finished
                return (continuation, true)
            case .pendingResult, .abandonedBeforeWait, .finished:
                return (nil, false)
            }
        }
        continuation?.resume(with: result)
        return accepted
    }

    /// Gives up the wait: resumes the awaiting task with `error` and fires its
    /// `onAbandon` handler. A pending, not-yet-consumed result is overridden.
    func abandon(throwing error: Error) {
        let waiting: (CheckedContinuation<T, Error>, (@Sendable () -> Void)?)? = state.withLock { current in
            switch current {
            case .idle, .pendingResult:
                current = .abandonedBeforeWait(error)
                return nil
            case let .waiting(continuation, onAbandon):
                current = .finished
                return (continuation, onAbandon)
            case .abandonedBeforeWait, .finished:
                return nil
            }
        }
        guard let (continuation, onAbandon) = waiting else { return }
        onAbandon?()
        continuation.resume(throwing: error)
    }
}

//
//  ModelToolApprovalGate.swift
//  FlowDown
//

import Combine
import Foundation

/// A call waiting for the user, as its card shows it.
struct ModelToolApprovalRequest: Identifiable, Equatable, Sendable {
    let id: UUID
    let toolName: String
    let icon: String
    /// Where the tool comes from, such as its MCP server; nil for built-ins.
    let source: String?
    /// Why the model made the call, in its own words.
    let reason: String?
    /// What the call will do, from the tool; nil shows the arguments.
    let summary: String?
    /// The arguments as the tool reads them, as JSON.
    let arguments: String
}

enum ModelToolApprovalDecision: Sendable, Equatable {
    case approve
    case deny
}

/// Holds the call that waits for the user. The pending request is what the
/// composer shows in place of the input; a decision, or the turn being
/// cancelled, resumes the call. Nothing approves by default.
final class ModelToolApprovalGate: @unchecked Sendable {
    /// Published on the main queue.
    let pendingRequest = CurrentValueSubject<ModelToolApprovalRequest?, Never>(nil)

    private let lock = NSLock()
    private var waiting: (id: UUID, continuation: CheckedContinuation<ModelToolApprovalDecision, Never>)?

    /// Shows `request` and suspends until the user decides. A cancelled task
    /// is denied, before or while it waits.
    func request(_ request: ModelToolApprovalRequest) async -> ModelToolApprovalDecision {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume(returning: .deny)
                    return
                }
                let replaced = waiting
                waiting = (request.id, continuation)
                lock.unlock()
                // Calls run one at a time; anything still waiting is stale.
                replaced?.continuation.resume(returning: .deny)
                publish(request)
            }
        } onCancel: {
            resolve(request.id, with: .deny)
        }
    }

    /// Answers the request with `id`; ignored when it no longer waits.
    func resolve(_ id: UUID, with decision: ModelToolApprovalDecision) {
        lock.lock()
        guard let entry = waiting, entry.id == id else {
            lock.unlock()
            return
        }
        waiting = nil
        lock.unlock()
        publish(nil)
        entry.continuation.resume(returning: decision)
    }

    private func publish(_ request: ModelToolApprovalRequest?) {
        DispatchQueue.main.async {
            self.pendingRequest.send(request)
        }
    }
}

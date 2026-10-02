//
//  ConversationSessionDeinitTests.swift
//  FlowDownUnitTests
//

import Combine
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationSessionDeinitTests {
    @Test(.timeLimit(.minutes(1)))
    @MainActor
    func releaseOffMainThread_marksSessionCompletedOnMainThread() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Deinit Tests \(UUID().uuidString.prefix(8))")
        }
        let identifier = conversation.id
        defer { ConversationManager.shared.deleteConversation(identifier: identifier) }

        let holder = SessionHolder()
        holder.session = ConversationSessionManager.shared.session(for: identifier)
        // Leave the holder with the last reference, and give deinit an
        // execution state to clear.
        ConversationSessionManager.shared.invalidateSession(for: identifier)
        ConversationSessionManager.shared.markSessionExecuting(identifier)

        let completedOnMainThread: Bool = await withCheckedContinuation { continuation in
            holder.cancellable = ConversationSessionManager.shared.executingSessionsPublisher
                .first { !$0.contains(identifier) }
                .sink { _ in continuation.resume(returning: Thread.isMainThread) }
            Task.detached { holder.session = nil }
        }

        #expect(completedOnMainThread)
        #expect(!ConversationSessionManager.shared.isSessionExecuting(identifier))
    }
}

private final class SessionHolder: @unchecked Sendable {
    var session: ConversationSession?
    var cancellable: AnyCancellable?
}

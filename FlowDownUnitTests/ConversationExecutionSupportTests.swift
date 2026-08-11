import Combine
@preconcurrency @testable import FlowDown
import Foundation
import ListViewKit
import Storage
import Testing
import UIKit

@Suite(.serialized)
struct ConversationExecutionSupportTests {
    @Test
    @MainActor
    func `request link content index stores urls with incrementing references`() async throws {
        try await withTemporarySession { _, session in
            let firstURL = URL(string: "https://example.com/one")!
            let secondURL = URL(string: "https://example.com/two")!

            let indices = try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let firstIndex = session.requestLinkContentIndex(firstURL)
                    let secondIndex = session.requestLinkContentIndex(secondURL)
                    continuation.resume(returning: (firstIndex, secondIndex))
                }
            }

            #expect(indices.0 == 1)
            #expect(indices.1 == 2)
            #expect(session.linkedContents[indices.0] == firstURL)
            #expect(session.linkedContents[indices.1] == secondURL)
        }
    }

    @Test
    @MainActor
    func `cancelCurrentTask waits for task teardown and clears executing state`() async throws {
        try await withTemporarySession { _, session in
            ConversationSessionManager.shared.markSessionExecuting(session.id)

            session.currentTask = Task { [weak session] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(10))
                }
                session?.currentTask = nil
            }

            await withCheckedContinuation { continuation in
                session.cancelCurrentTask {
                    continuation.resume()
                }
            }

            #expect(session.currentTask == nil)
            #expect(!ConversationSessionManager.shared.isSessionExecuting(session.id))
        }
    }

    @Test
    @MainActor
    func `activity indicator drives the loading row and requestUpdate republishes messages`() async throws {
        try await withTemporarySession { _, session in
            let message = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Hello FlowDown")
            }
            session.save()
            session.notifyMessagesDidChange()

            let listView = MessageListView()
            listView.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
            listView.session = session
            listView.layoutIfNeeded()

            try await waitUntil {
                snapshotEntries(in: listView).contains {
                    if case let .userContent(messageID, _) = $0 {
                        return messageID == message.id
                    }
                    return false
                }
            }

            var publisherEmissionCount = 0
            let cancellable = session.messagesDidChange
                .dropFirst()
                .sink { _ in
                    publisherEmissionCount += 1
                }
            defer { cancellable.cancel() }

            session.showActivity("Working")
            try await waitUntil {
                snapshotEntries(in: listView).contains {
                    if case let .activityReporting(content) = $0 {
                        return content == "Working"
                    }
                    return false
                }
            }

            // requestUpdate republishes messages but no longer touches the
            // indicator — the activity row must survive it.
            await session.requestUpdate()
            try await waitUntil {
                publisherEmissionCount >= 1
            }
            #expect(snapshotEntries(in: listView).contains {
                if case .activityReporting = $0 { return true }
                return false
            })

            session.endActivity()

            try await waitUntil {
                let snapshot = snapshotEntries(in: listView)
                let hasUserMessage = snapshot.contains {
                    if case let .userContent(messageID, _) = $0 {
                        return messageID == message.id
                    }
                    return false
                }
                let hasLoadingEntry = snapshot.contains {
                    if case .activityReporting = $0 {
                        return true
                    }
                    return false
                }
                return hasUserMessage && !hasLoadingEntry
            }
        }
    }
}

private extension ConversationExecutionSupportTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (Conversation, ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Execution Support \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(conversation, session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }

    @MainActor
    func waitUntil(
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(20),
        _ condition: @MainActor () -> Bool,
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw NSError(
            domain: "ConversationExecutionSupportTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for condition."],
        )
    }

    @MainActor
    func snapshotEntries(in listView: MessageListView) -> [MessageListView.Entry] {
        listView.entries
    }
}

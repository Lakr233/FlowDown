@testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ConversationMCPSignInHintTests {
    @Test
    @MainActor
    func signInHints_oncePerServerPerConversation() async throws {
        try await withTemporarySession { session in
            func hints() -> [String] {
                session.messages.filter { $0.role == .hint }.map(\.document)
            }

            // Two servers need sign-in; unrelated failures add nothing, and a
            // server reported twice in one turn is mentioned once.
            await session.noteMCPAuthorizationProblems([
                FlowDown.MCPError.signInRequired("Alpha"),
                FlowDown.MCPError.connectionFailed,
                FlowDown.MCPError.clientIDRequired("Beta"),
                FlowDown.MCPError.signInRequired("Alpha"),
                CancellationError(),
            ])
            let first = hints()
            #expect(first == [
                FlowDown.MCPError.signInRequired("Alpha").localizedDescription,
                FlowDown.MCPError.clientIDRequired("Beta").localizedDescription,
            ])

            // The next turn repeats them: no new hints.
            await session.noteMCPAuthorizationProblems([
                FlowDown.MCPError.signInRequired("Alpha"),
                FlowDown.MCPError.clientIDRequired("Beta"),
            ])
            #expect(hints() == first)

            // A newly affected server gets its own hint.
            await session.noteMCPAuthorizationProblems([
                FlowDown.MCPError.signInRequired("Alpha"),
                FlowDown.MCPError.authorizationUnsupported("Gamma"),
            ])
            #expect(hints() == first + [FlowDown.MCPError.authorizationUnsupported("Gamma").localizedDescription])

            // Nothing at all when every server is fine.
            await session.noteMCPAuthorizationProblems([])
            #expect(hints().count == 3)
        }
    }

    @Test
    @MainActor
    func signInHints_areTrackedPerConversation() async throws {
        try await withTemporarySession { first in
            await first.noteMCPAuthorizationProblems([FlowDown.MCPError.signInRequired("Alpha")])
            #expect(first.messages.filter { $0.role == .hint }.count == 1)
            try await withTemporarySession { second in
                await second.noteMCPAuthorizationProblems([FlowDown.MCPError.signInRequired("Alpha")])
                #expect(second.messages.filter { $0.role == .hint }.count == 1)
            }
        }
    }
}

private extension ConversationMCPSignInHintTests {
    @MainActor
    func withTemporarySession(
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "MCP Sign-In Hint Tests \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }
}

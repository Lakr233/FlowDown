@testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ShortcutsScopeTests {
    @Test
    func `new conversation url encodes message content for shortcuts`() throws {
        let nilURL = try ShortcutUtilities.newConversationURL(initialMessage: nil)
        let encodedURL = try ShortcutUtilities.newConversationURL(initialMessage: "Hello/World?")

        #expect(nilURL.absoluteString == "flowdown://new/%20")
        #expect(encodedURL.absoluteString == "flowdown://new/Hello%2FWorld%3F")
    }

    @Test
    func `latest conversation transcript includes title user assistant and reasoning`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let unique = UUID().uuidString
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Unit \(unique)")
        }
        let userMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .user)
            message.update(\.document, to: "Hello \(unique)")
        }
        let assistantMessage = sdb.makeMessage(with: conversation.id) { message in
            message.update(\.role, to: .assistant)
            message.update(\.document, to: "Reply \(unique)")
            message.update(\.reasoningContent, to: "Because \(unique)")
        }

        sdb.messagePut(messages: [userMessage, assistantMessage])

        let transcript = try ShortcutUtilities.latestConversationTranscript()

        #expect(transcript.contains("# Unit \(unique)"))
        #expect(transcript.contains("Hello \(unique)"))
        #expect(transcript.contains("Reply \(unique)"))
        #expect(transcript.contains("Because \(unique)"))
    }

    @Test
    func `shortcut related errors expose localized descriptions`() {
        let shortcutErrors: [ShortcutError] = [
            .emptyMessage,
            .modelUnavailable,
            .emptyResponse,
            .imageNotAllowed,
            .imageNotSupportedByModel,
            .invalidImage,
            .audioNotAllowed,
            .audioNotSupportedByModel,
            .invalidAudio,
            .invalidCandidates,
        ]
        let utilityErrors: [ShortcutUtilitiesError] = [
            .unableToCreateURL,
            .invalidMessageEncoding,
            .conversationNotFound,
            .conversationHasNoMessages,
        ]

        for error in shortcutErrors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
        for error in utilityErrors {
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }
}

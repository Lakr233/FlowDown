import AppIntents
import Foundation
import Storage
import UIKit

enum ShortcutUtilitiesError: LocalizedError {
    case unableToCreateURL
    case invalidMessageEncoding
    case conversationNotFound
    case conversationHasNoMessages

    var errorDescription: String? {
        switch self {
        case .unableToCreateURL:
            String(localized: "Unable to construct URL.")
        case .invalidMessageEncoding:
            String(localized: "Unable to encode the provided message.")
        case .conversationNotFound:
            String(localized: "No conversations were found.")
        case .conversationHasNoMessages:
            String(localized: "The latest conversation does not contain any messages.")
        }
    }
}

enum ShortcutUtilities {
    static func latestConversationTranscript() throws -> String {
        guard let latestConversation = sdb.conversationList().first else {
            throw ShortcutUtilitiesError.conversationNotFound
        }

        let messages = sdb.listMessages(within: latestConversation.id)
            .filter { [.user, .assistant].contains($0.role) }

        guard !messages.isEmpty else {
            throw ShortcutUtilitiesError.conversationHasNoMessages
        }

        let title = latestConversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        var transcript: [String] = []
        if !title.isEmpty {
            transcript.append("# \(title)")
        }

        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .short

        for message in messages {
            let role = message.role == .user
                ? String(localized: "User")
                : String(localized: "Assistant")

            let timestamp = formatter.string(from: message.creation)
            var contentParts: [String] = []

            let mainContent = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            if !mainContent.isEmpty {
                contentParts.append(mainContent)
            }

            let reasoning = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
            if !reasoning.isEmpty, message.role == .assistant {
                contentParts.append(String(localized: "(Reasoning) \(reasoning)"))
            }

            transcript.append("**\(role)** [\(timestamp)]\n\(contentParts.joined(separator: "\n\n"))")
        }

        return transcript.joined(separator: "\n\n")
    }

    static func newConversationURL(initialMessage: String?) throws -> URL {
        let allowedCharacters = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let messageForEncoding: String = if let initialMessage, !initialMessage.isEmpty {
            initialMessage
        } else {
            " "
        }

        guard let encodedMessage = messageForEncoding.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
            throw ShortcutUtilitiesError.invalidMessageEncoding
        }

        guard let url = URL(string: "flowdown://new/\(encodedMessage)") else {
            throw ShortcutUtilitiesError.unableToCreateURL
        }

        return url
    }
}

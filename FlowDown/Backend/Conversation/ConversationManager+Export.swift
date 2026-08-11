//
//  ConversationManager+Export.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/30/25.
//

import Foundation
import Storage

extension ConversationManager {
    enum ExportFormat: String {
        case plainText
        case markdown
    }

    func exportConversation(
        identifier: Conversation.ID,
        exportFormat: ExportFormat,
        completion: @escaping (Result<String, Error>) -> Void,
    ) {
        guard let conversation = ConversationManager.shared.conversation(identifier: identifier) else {
            assertionFailure()
            completion(.failure(NSError(domain: "ConversationManager", code: 404, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Unknown Error"),
            ])))
            return
        }
        let session = ConversationSessionManager.shared.session(for: identifier)

        let messages: [String] = session.messages.map { message in
            switch exportFormat {
            case .plainText:
                Self.joined([
                    message.role.rawValue.capitalized,
                    message.creation.formatted(date: .abbreviated, time: .omitted),
                    message.reasoningContent,
                    message.document,
                ], separator: "\n")
            case .markdown:
                Self.joined([
                    "## \(message.role.rawValue.capitalized) - \(message.creation.formatted(date: .abbreviated, time: .omitted))",
                    message.reasoningContent.isEmpty ? "" : " > \(message.reasoningContent)",
                    message.document,
                ], separator: "\n\n")
            }
        }

        let header = String(localized: "Exported Conversation - \(conversation.title)")
        let separator = switch exportFormat {
        case .plainText: "\n\n"
        case .markdown: "\n\n---\n\n"
        }
        completion(.success(Self.joined([header] + messages, separator: separator)))
    }

    /// Trims every component and drops the empty ones before joining, so a
    /// missing reasoning block never leaves a blank line behind.
    private static func joined(_ components: [String], separator: String) -> String {
        components
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: separator)
    }
}

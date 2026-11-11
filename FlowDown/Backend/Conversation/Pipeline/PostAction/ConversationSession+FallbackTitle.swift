//
//  ConversationSession+FallbackTitle.swift
//  FlowDown
//

import Foundation
import Storage

/// The title a conversation shows while it has none of its own (auto-rename
/// is off, generation failed or has not finished): the first text the user
/// wrote, on one line.
enum ConversationFallbackTitle {
    /// Characters kept from the message before the ellipsis. Independent of
    /// the generated title limit.
    static let lengthLimit = 50

    /// The text on one line: runs of whitespace, newlines included, become a
    /// single space and the ends are trimmed. Text longer than the limit keeps
    /// its first 50 characters (a space the cut ends on is dropped) followed by
    /// "…". Characters are counted as `Character`s, so an emoji or a CJK
    /// ideograph counts as one. Nil for blank text.
    static func make(from text: String) -> String? {
        let collapsed = text
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        guard collapsed.count > lengthLimit else { return collapsed }
        let cut = collapsed
            .prefix(lengthLimit)
            .trimmingCharacters(in: .whitespaces)
        return cut + "…"
    }

    /// Whether the title is the name a new conversation starts with, in any
    /// shipped language (a synced conversation may come from a device in
    /// another one), or blank.
    static func isDefault(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty
            || trimmed == String(localized: "Conversation")
            || defaultTitles.contains(trimmed)
    }

    /// Whether the text is the caption the editor sends in place of an empty
    /// message that carries only attachments ("Attached 2 Documents"), in any
    /// shipped language.
    static func isAttachmentCaption(_ text: String) -> Bool {
        attachmentCaptionFormats.contains { prefix, suffix in
            guard text.count > prefix.count + suffix.count,
                  text.hasPrefix(prefix),
                  text.hasSuffix(suffix)
            else { return false }
            let count = text.dropFirst(prefix.count).dropLast(suffix.count)
            return count.allSatisfy(\.isASCIIDigit)
        }
    }

    private static let defaultTitleKey = "Conversation"
    private static let attachmentCaptionKey = "Attached %lld Documents"

    private static let defaultTitles: Set<String> = Set(
        localizedValues(forKey: defaultTitleKey).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        },
    )

    private static let attachmentCaptionFormats: [(prefix: String, suffix: String)] =
        localizedValues(forKey: attachmentCaptionKey).compactMap { format in
            guard let range = format.range(of: "%lld") else { return nil }
            return (String(format[..<range.lowerBound]), String(format[range.upperBound...]))
        }

    private static func localizedValues(forKey key: String) -> Set<String> {
        var values: Set<String> = [key]
        for localization in Bundle.main.localizations {
            guard let path = Bundle.main.path(forResource: localization, ofType: "lproj"),
                  let bundle = Bundle(path: path)
            else { continue }
            values.insert(bundle.localizedString(forKey: key, value: nil, table: nil))
        }
        return values
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

extension ConversationManager {
    /// Whether the conversation has no title of its own yet: it still has the
    /// default name, or auto-rename may still replace what it shows (a
    /// template's name, or an earlier fallback). A generated title or a rename
    /// turns auto-rename off, so neither counts unless it is the default name.
    func hasPlaceholderTitle(_ conversation: Conversation) -> Bool {
        conversation.shouldAutoRename || ConversationFallbackTitle.isDefault(conversation.title)
    }

    /// Shows `title` while the conversation has no title of its own. Leaves
    /// `shouldAutoRename` alone, so a generated title still replaces it.
    func applyFallbackTitle(_ title: String, to identifier: Conversation.ID) {
        guard let conversation = conversation(identifier: identifier),
              conversation.title != title,
              hasPlaceholderTitle(conversation)
        else { return }
        editConversation(identifier: identifier) {
            $0.update(\.title, to: title)
        }
    }
}

extension ConversationSession {
    /// The fallback title from the first user message with text of its own.
    /// Skips messages that only carried attachments: rows the pipeline added
    /// for them, and sends with no text, which the editor stores as an
    /// "Attached N Documents" caption. Nil when there is no such message.
    func firstMessageTitle() -> String? {
        messages
            .lazy
            .filter { $0.role == .user && !self.isAttachmentHolder($0) }
            .filter { !self.isAttachmentCaption($0) }
            .compactMap { ConversationFallbackTitle.make(from: $0.document) }
            .first
    }

    /// Shows the first message as the title while the conversation has none
    /// of its own; called when the user sends a message and when a
    /// conversation opens, which also fixes ones left on the default name.
    func applyFallbackTitleIfNeeded() {
        guard let title = firstMessageTitle() else { return }
        ConversationManager.shared.applyFallbackTitle(title, to: id)
    }

    private func isAttachmentCaption(_ message: Message) -> Bool {
        !attachments(for: message.objectId).isEmpty
            && ConversationFallbackTitle.isAttachmentCaption(message.document)
    }
}

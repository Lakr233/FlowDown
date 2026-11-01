//
//  Created by ktiays on 2025/2/11.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Storage
import UIKit

extension MessageListView {
    enum Entry: Identifiable, Hashable {
        /// A user message: its attachments over its text.
        case userContent(Message.ID, MessageRepresentation, Attachments)
        /// Thoughts and tool calls folded into one line.
        case activity(ActivitySummary)
        case aiContent(Message.ID, MessageRepresentation)
        case hint(String, String)
        case webSearchContent(Message.WebSearchStatus)
        case activityReporting(String)

        var id: String {
            switch self {
            case let .userContent(_, message, _):
                "UserContent.\(message.id)"
            case let .activity(summary):
                summary.id
            case let .aiContent(_, message):
                "AiContent.\(message.id)"
            case let .hint(id, _):
                "Hint.\(id)"
            case let .webSearchContent(status):
                "WebSearchContent.\(status.id)"
            case .activityReporting:
                // Stable identity: the loading indicator is a single row whose
                // text changes while streaming. Deriving the id from the content
                // would remove/insert the row (with fade animations) on every
                // update instead of reconfiguring it in place.
                "ActivityReporting"
            }
        }
    }

    struct MessageRepresentation: Identifiable, Hashable {
        var id: Message.ID
        var createAt: Date
        var role: Message.Role
        var content: String
        /// Whether this is the reply still being written.
        var isStreaming: Bool

        init(from message: Message) {
            id = message.objectId
            createAt = message.creation
            role = message.role
            content = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            isStreaming = false
        }
    }

    struct Attachments: Identifiable, Hashable {
        typealias Item = AttachmentsBar.Item

        var items: [Item]
        var id: String {
            items.reduce(into: .init()) { result, item in
                result += item.id.uuidString
            }
        }
    }

    // MARK: - Convert Messages to Entries

    /// What `ConversationSession` puts in a reply that has reasoning but no text.
    private static let emptyReplyPlaceholder = String(localized: "Empty message.")

    /// Converts messages to entries. While the session is executing, its last
    /// assistant reply is the one still being written and is marked streaming.
    func entries(from messages: [Message], isExecuting: Bool) -> [Entry] {
        let streamingMessageID = isExecuting
            ? messages.last(where: { $0.role == .assistant })?.objectId
            : nil
        var entries: [Entry] = []
        var latestDay: Date?

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dayKeyFormatter = DateFormatter()
        dayKeyFormatter.dateFormat = "yyyy-MM-dd"

        func checkAddDateHint(_ date: Date) {
            func addDateHint(_ date: Date) {
                latestDay = date
                let hint = dateFormatter.string(from: date)
                let dayKey = dayKeyFormatter.string(from: date)
                entries.append(.hint("date.\(dayKey)", hint))
            }
            if let latestDay {
                if !Calendar.current.isDate(date, inSameDayAs: latestDay) {
                    addDateHint(date)
                }
            } else {
                addDateHint(date)
            }
        }

        var summary: ActivitySummary?
        func fold(_ step: ActivitySummary.Step, of message: Message, thinkingDuration: TimeInterval = 0) {
            if summary == nil {
                checkAddDateHint(message.creation)
                summary = .init(startingWith: message.objectId)
            }
            summary?.steps.append(step)
            summary?.thinkingDuration += thinkingDuration
        }
        func endSummary() {
            guard let finished = summary else { return }
            entries.append(.activity(finished))
            summary = nil
        }

        for message in messages {
            switch message.role {
            // MARK: - User Message

            case .user:
                endSummary()
                let attachmentItems: [Attachments.Item] = session.attachments(for: message.objectId).compactMap {
                    guard let uuid = UUID(uuidString: $0.id) else {
                        return nil
                    }
                    guard let type = RichEditorView.Object.Attachment.AttachmentType(rawValue: $0.type) else {
                        return nil
                    }
                    return .init(
                        id: uuid,
                        type: type,
                        name: $0.name,
                        previewImage: $0.previewImageData,
                        imageRepresentation: $0.imageRepresentation,
                        textRepresentation: $0.representedDocument,
                        storageSuffix: $0.storageSuffix,
                    )
                }
                if !attachmentItems.isEmpty || !message.document.isEmpty {
                    checkAddDateHint(message.creation)
                    entries.append(.userContent(
                        message.objectId,
                        .init(from: message),
                        .init(items: attachmentItems),
                    ))
                }
                assert(message.reasoningContent.isEmpty)

            // MARK: - Assistant Message

            case .assistant:
                let reasoningContent = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
                var messageContent = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
                // The session fills a reply that only thought with a placeholder
                // when it loads, so the reply never reads as still thinking. In
                // the summary that reply has no text, and the thought folds in
                // with the calls after it.
                if !reasoningContent.isEmpty, messageContent == Self.emptyReplyPlaceholder {
                    messageContent = ""
                }
                if !reasoningContent.isEmpty {
                    fold(
                        .thought(message.objectId, text: reasoningContent),
                        of: message,
                        thinkingDuration: message.thinkingDuration,
                    )
                }
                if !messageContent.isEmpty {
                    endSummary()
                    checkAddDateHint(message.creation)
                    var representation = MessageRepresentation(from: message)
                    representation.isStreaming = message.objectId == streamingMessageID
                    entries.append(.aiContent(message.objectId, representation))
                }

            // MARK: - Web Search

            case .webSearch:
                endSummary()
                checkAddDateHint(message.creation)
                entries.append(.webSearchContent(message.webSearchStatus))

            // MARK: - Activity Reporting

            case .hint:
                endSummary()
                checkAddDateHint(message.creation)
                entries.append(.hint("message.\(message.objectId)", message.document))

            // MARK: - Tool Call Status

            case .toolHint:
                fold(.tool(message.objectId, status: message.toolStatus), of: message)

            // MARK: - Drop Unrelated

            default:
                break
            }
        }
        // While the session runs, the summary nothing has come after is the
        // one the turn is still at work on.
        summary?.isRunning = isExecuting
        endSummary()
        return entries
    }
}

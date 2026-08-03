//
//  Created by ktiays on 2025/2/11.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Storage
import UIKit

extension MessageListView {
    enum Entry: Identifiable, Hashable {
        case userContent(Message.ID, MessageRepresentation)
        case userAttachment(Message.ID, Attachments)
        case reasoningContent(Message.ID, MessageRepresentation)
        case aiContent(Message.ID, MessageRepresentation)
        case hint(String, String)
        case webSearchContent(Message.WebSearchStatus)
        case activityReporting(String)
        case toolCallStatus(Message.ID, Message.ToolStatus)

        var id: String {
            switch self {
            case let .userContent(_, message):
                "UserContent.\(message.id)"
            case let .userAttachment(_, message):
                "UserAttachment.\(message.id)"
            case let .reasoningContent(_, message):
                "ReasoningContent.\(message.id)"
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
            case let .toolCallStatus(messageID, status):
                "ToolCallStatus.\(messageID).\(status.id)"
            }
        }
    }

    struct MessageRepresentation: Identifiable, Hashable {
        var id: Message.ID
        var createAt: Date
        var role: Message.Role
        var content: String
        var isRevealed: Bool
        var isThinking: Bool
        var thinkingDuration: TimeInterval

        init(from message: Message) {
            id = message.objectId
            createAt = message.creation
            role = message.role
            content = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            isRevealed = true
            isThinking = false
            thinkingDuration = 0
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

    func entries(from messages: [Message]) -> [Entry] {
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

        for message in messages {
            switch message.role {
            // MARK: - User Message

            case .user:
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
                if !attachmentItems.isEmpty {
                    checkAddDateHint(message.creation)
                    entries.append(.userAttachment(message.objectId, .init(items: attachmentItems)))
                }
                if !message.document.isEmpty {
                    checkAddDateHint(message.creation)
                    entries.append(.userContent(message.objectId, .init(from: message)))
                }
                assert(message.reasoningContent.isEmpty)

            // MARK: - Assistant Message

            case .assistant:
                let reasoningContent = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
                let messageContent = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
                if !reasoningContent.isEmpty {
                    checkAddDateHint(message.creation)
                    var representation = MessageRepresentation(from: message)
                    representation.id = message.combinationID
                    representation.content = reasoningContent
                    representation.isRevealed = !message.isThinkingFold
                    representation.isThinking = messageContent.isEmpty
                    representation.thinkingDuration = message.thinkingDuration
                    entries.append(.reasoningContent(message.objectId, representation))
                }
                if !messageContent.isEmpty {
                    checkAddDateHint(message.creation)
                    entries.append(.aiContent(message.objectId, .init(from: message)))
                }

            // MARK: - Web Search

            case .webSearch:
                checkAddDateHint(message.creation)
                entries.append(.webSearchContent(message.webSearchStatus))

            // MARK: - Activity Reporting

            case .hint:
                checkAddDateHint(message.creation)
                entries.append(.hint("message.\(message.objectId)", message.document))

            // MARK: - Tool Call Status

            case .toolHint:
                checkAddDateHint(message.creation)
                entries.append(.toolCallStatus(message.objectId, message.toolStatus))

            // MARK: - Drop Unrelated

            default:
                break
            }
        }
        return entries
    }
}

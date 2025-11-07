import AppIntents
import Foundation
import Storage

struct SearchConversationsIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Search Conversations")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Search saved conversations by keyword and return formatted summaries."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Keyword"),
        default: nil
    )
    var keyword: String?

    @Parameter(
        title: LocalizedStringResource("Result Limit"),
        default: 5,
        requestValueDialog: IntentDialog("How many results should FlowDown return?")
    )
    var resultLimit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search conversations") {
            \.$keyword
            \.$resultLimit
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let sanitizedKeyword = keyword?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let normalizedLimit = SearchConversationsIntentHelper.normalizeLimit(resultLimit)

        let results = SearchConversationsIntentHelper.search(
            keyword: sanitizedKeyword,
            maxResults: normalizedLimit
        )

        if results.isEmpty {
            let fallback = String(localized: "No conversations found.")
            let dialog = IntentDialog(.init(stringLiteral: fallback))
            return .result(value: [fallback], dialog: dialog)
        }

        let summaryFormat = String(
            localized: "%d conversation(s) matched your criteria."
        )
        let dialogMessage = String(format: summaryFormat, results.count)
        let dialog = IntentDialog(.init(stringLiteral: dialogMessage))
        return .result(value: results, dialog: dialog)
    }
}

enum SearchConversationsIntentHelper {
    private static let maximumResultLimit = 50

    static func normalizeLimit(_ limit: Int) -> Int {
        let clamped = min(max(limit, 1), maximumResultLimit)
        return clamped
    }

    static func search(
        keyword: String?,
        maxResults: Int
    ) -> [String] {
        let conversations = sdb.conversationList()
        guard !conversations.isEmpty else { return [] }

        var results: [String] = []
        let limit = normalizeLimit(maxResults)
        let headerFormatter = DateFormatter()
        headerFormatter.dateStyle = .medium
        headerFormatter.timeStyle = .short

        let messageFormatter = DateFormatter()
        messageFormatter.dateStyle = .short
        messageFormatter.timeStyle = .short

        for conversation in conversations {
            let messages = sdb
                .listMessages(within: conversation.id)
                .filter { [.user, .assistant].contains($0.role) }

            if messages.isEmpty {
                continue
            }

            let filteredMessages: [Message]
            if let keyword, !keyword.isEmpty {
                filteredMessages = messages.filter { message in
                    message.matches(keyword: keyword)
                }
                if filteredMessages.isEmpty {
                    continue
                }
            } else {
                filteredMessages = messages
            }

            let formatted = formatResult(
                conversation: conversation,
                messages: filteredMessages,
                headerFormatter: headerFormatter,
                messageFormatter: messageFormatter
            )
            results.append(formatted)

            if results.count >= limit {
                break
            }
        }

        return results
    }

    private static func formatResult(
        conversation: Conversation,
        messages: [Message],
        headerFormatter: DateFormatter,
        messageFormatter: DateFormatter
    ) -> String {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "Conversation")
        let headerFormat = String(
            localized: "%@ • %@"
        )
        let header = String(format: headerFormat, title, headerFormatter.string(from: conversation.creation))

        let limitedMessages = messages.prefix(10)

        let body = limitedMessages.map { message -> String in
            let roleDescription: String = switch message.role {
            case .user:
                String(localized: "User")
            case .assistant:
                String(localized: "Assistant")
            default:
                message.role.rawValue.capitalized
            }

            let timestamp = messageFormatter.string(from: message.creation)
            var contents = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
            if contents.isEmpty {
                contents = message.reasoningContent.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if contents.isEmpty {
                contents = String(localized: "(No Content)")
            }

            let entryHeaderFormat = String(
                localized: "[%@] %@"
            )
            let entryHeader = String(format: entryHeaderFormat, timestamp, roleDescription)

            return [entryHeader, contents].joined(separator: "\n")
        }

        let result = ([header] + body).joined(separator: "\n\n")
        return result
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private extension Message {
    func matches(keyword: String) -> Bool {
        let lowercasedKeyword = keyword.lowercased()
        if document.lowercased().contains(lowercasedKeyword) { return true }
        if reasoningContent.lowercased().contains(lowercasedKeyword) { return true }
        return false
    }
}

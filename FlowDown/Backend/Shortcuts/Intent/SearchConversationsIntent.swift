import AppIntents
import Foundation
import Storage

struct SearchConversationsIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Search Conversations"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Search saved conversations by keyword and return formatted summaries."),
            categoryName: LocalizedStringResource("Conversations"),
        )
    }

    static var authenticationPolicy: IntentAuthenticationPolicy {
        .requiresAuthentication
    }

    @Parameter(
        title: "Keyword",
        default: "",
        requestValueDialog: "Enter a keyword to search for in your conversations. Leave empty to return recent conversations."
    )
    var keyword: String

    @Parameter(title: "Result Limit", default: 5, requestValueDialog: "How many results should we return?")
    var resultLimit: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Search saved conversations by \(\.$keyword)") {
            \.$resultLimit
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<[String]> & ProvidesDialog {
        let sanitizedKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        let results = SearchConversationsIntentHelper.search(
            keyword: sanitizedKeyword,
            maxResults: resultLimit,
        )

        if results.isEmpty {
            let fallback = String(localized: "No conversations found.")
            let dialog = IntentDialog(.init(stringLiteral: fallback))
            return .result(value: [fallback], dialog: dialog)
        }

        let summaryFormat = String(
            localized: "%d conversation(s) matched your criteria.",
        )
        let dialogMessage = String(format: summaryFormat, results.count)
        let dialog = IntentDialog(.init(stringLiteral: dialogMessage))
        return .result(value: results, dialog: dialog)
    }
}

enum SearchConversationsIntentHelper {
    private static let maximumResultLimit = 50

    private static func normalizeLimit(_ limit: Int) -> Int {
        min(max(limit, 1), maximumResultLimit)
    }

    static func search(
        keyword: String?,
        maxResults: Int,
    ) -> [String] {
        let conversations = sdb.conversationList()

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
                messageFormatter: messageFormatter,
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
        messageFormatter: DateFormatter,
    ) -> String {
        let title = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? String(localized: "Conversation")
        let header = String(format: "%@ • %@", title, headerFormatter.string(from: conversation.creation))

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

            let entryHeader = String(format: "[%@] %@", timestamp, roleDescription)

            return [entryHeader, contents].joined(separator: "\n")
        }

        return ([header] + body).joined(separator: "\n\n")
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

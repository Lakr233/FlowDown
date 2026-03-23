//
//  ConversationSummarizer.swift
//  FlowDown
//
//  Created by Alan Ye on 3/23/26.
//

import ChatClientKit
import Foundation
import Storage

@MainActor
final class ConversationSummarizer {
    static let shared = ConversationSummarizer()

    private var summarizedThisSession: Set<Conversation.ID> = []

    private init() {}

    // MARK: - Public API

    func summarizeIfNeeded(
        conversationId: Conversation.ID,
        messages: [Message],
        using modelId: ModelManager.ModelIdentifier?
    ) async {
        guard let modelId else {
            Logger.model.debugFile("[Summarizer] skipping: no model id")
            return
        }
        guard !summarizedThisSession.contains(conversationId) else {
            Logger.model.debugFile("[Summarizer] skipping: already summarized \(conversationId) this session")
            return
        }

        let userMessages = messages.filter { $0.role == .user }
        guard userMessages.count >= 3 else {
            Logger.model.debugFile("[Summarizer] skipping: fewer than 3 user messages")
            return
        }

        // Check if existing summary is stale enough to warrant a refresh
        do {
            let storage = try Storage.db()
            if let existing = try storage.getSummary(forConversation: conversationId) {
                let delta = messages.count - existing.messageCount
                if delta < 2 {
                    Logger.model.debugFile("[Summarizer] skipping: message count delta \(delta) < 2")
                    return
                }
            }
        } catch {
            Logger.model.errorFile("[Summarizer] failed to read existing summary: \(error)")
            return
        }

        // Build conversation text from user/assistant messages
        var conversationLines: [String] = []
        for message in messages {
            switch message.role {
            case .user:
                let text = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                conversationLines.append("User: \(text)")
            case .assistant:
                let text = message.document.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                conversationLines.append("Assistant: \(text)")
            default:
                continue
            }
        }

        var conversationText = conversationLines.joined(separator: "\n")
        if conversationText.count > 4000 {
            conversationText = String(conversationText.prefix(4000))
        }

        guard !conversationText.isEmpty else {
            Logger.model.debugFile("[Summarizer] skipping: no usable conversation text")
            return
        }

        let systemPrompt = """
        Summarize the following conversation concisely. \
        Respond in exactly this format (no extra text):
        SUMMARY: <one or two sentence summary>
        TOPICS: <comma-separated list of key topics>
        """

        let inferMessages: [ChatRequestBody.Message] = [
            .system(content: .text(systemPrompt)),
            .user(content: .text(conversationText)),
        ]

        Logger.model.infoFile("[Summarizer] generating summary for conversation \(conversationId)")

        do {
            let response = try await ModelManager.shared.infer(
                with: modelId,
                maxCompletionTokens: 256,
                input: inferMessages
            )

            let raw = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let (summary, topics) = parseResponse(raw)

            guard !summary.isEmpty else {
                Logger.model.errorFile("[Summarizer] model returned empty summary for \(conversationId)")
                return
            }

            try saveSummary(
                conversationId: conversationId,
                summary: summary,
                topics: topics,
                messageCount: messages.count
            )

            summarizedThisSession.insert(conversationId)
            Logger.model.infoFile("[Summarizer] saved summary for \(conversationId), topics: \(topics)")
        } catch {
            Logger.model.errorFile("[Summarizer] inference failed for \(conversationId): \(error)")
        }
    }

    func formattedRecentSummaries(limit: Int = 15) async -> String? {
        do {
            let storage = try Storage.db()
            let summaries = try storage.getRecentSummaries(limit: limit)
            guard !summaries.isEmpty else { return nil }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "MMM d"

            var lines: [String] = ["Recent conversation context (for background awareness only):"]
            for (index, item) in summaries.enumerated() {
                let dateStr = dateFormatter.string(from: item.modified)
                let topicsStr = item.topics.trimmingCharacters(in: .whitespacesAndNewlines)
                let summaryStr = item.summary.trimmingCharacters(in: .whitespacesAndNewlines)
                if topicsStr.isEmpty {
                    lines.append("\(index + 1). [\(dateStr)] \(summaryStr)")
                } else {
                    lines.append("\(index + 1). [\(dateStr)] [\(topicsStr)] \(summaryStr)")
                }
            }

            return lines.joined(separator: "\n")
        } catch {
            Logger.model.errorFile("[Summarizer] failed to load recent summaries: \(error)")
            return nil
        }
    }

    // MARK: - Private Helpers

    private func parseResponse(_ raw: String) -> (summary: String, topics: String) {
        var summary = ""
        var topics = ""

        let lines = raw.components(separatedBy: "\n")
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix("summary:") {
                summary = String(trimmed.dropFirst("summary:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else if trimmed.lowercased().hasPrefix("topics:") {
                topics = String(trimmed.dropFirst("topics:".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        // Fallback: if parsing failed, use the whole response as the summary
        if summary.isEmpty {
            summary = raw
        }

        return (summary, topics)
    }

    private func saveSummary(
        conversationId: Conversation.ID,
        summary: String,
        topics: String,
        messageCount: Int
    ) throws {
        let storage = try Storage.db()
        if let existing = try storage.getSummary(forConversation: conversationId) {
            existing.update(\.summary, to: summary)
            existing.update(\.topics, to: topics)
            existing.update(\.messageCount, to: messageCount)
            try storage.insertOrUpdateSummary(existing)
        } else {
            let newSummary = ConversationSummary(
                deviceId: Storage.deviceId,
                conversationId: conversationId
            )
            newSummary.update(\.summary, to: summary)
            newSummary.update(\.topics, to: topics)
            newSummary.update(\.messageCount, to: messageCount)
            try storage.insertOrUpdateSummary(newSummary)
        }
    }
}

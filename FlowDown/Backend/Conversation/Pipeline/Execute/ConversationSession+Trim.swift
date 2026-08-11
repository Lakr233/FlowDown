//
//  ConversationSession+Trim.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation

extension ConversationSession {
    func removeOutOfContextContents(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ tools: [ChatRequestBody.Tool]?,
        _ modelContextLength: Int,
    ) throws -> Bool {
        let estimatedTokenCount = ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
            input: requestMessages,
            tools: tools ?? [],
        )
        Logger.model.debugFile("estimated token count: \(estimatedTokenCount)")

        guard estimatedTokenCount > modelContextLength else {
            return false
        }

        // Phase 1: Identify — collect indices of messages to evict (front-to-back, skip system)
        var indicesToEvict: [Int] = []
        var currentTokenCount = estimatedTokenCount

        for idx in 0 ..< requestMessages.count {
            guard currentTokenCount > modelContextLength else { break }
            let item = requestMessages[idx]
            if case .system = item { continue }
            indicesToEvict.append(idx)
            // Recalculate token count after virtually removing all collected indices so far
            var candidateMessages = requestMessages
            for evictIdx in indicesToEvict.reversed() {
                candidateMessages.remove(at: evictIdx)
            }
            currentTokenCount = ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: candidateMessages,
                tools: tools ?? [],
            )
        }

        guard !indicesToEvict.isEmpty else {
            Logger.model.errorFile("unable to remove any more messages, estimated token count: \(estimatedTokenCount)")
            throw NSError(
                domain: String(localized: "Inference Service"),
                code: 1,
                userInfo: ["reason": "unable to remove any more messages"],
            )
        }

        Logger.model.debugFile("evicting \(indicesToEvict.count) messages at indices: \(indicesToEvict)")

        // Phase 2: Summarize — build extractive summary from evicted messages
        let summaryBudget = modelContextLength / 10
        var summaryLines: [String] = []
        var summaryTokenCount = 0

        for idx in indicesToEvict {
            let rolePrefix: String
            let firstLine: String

            switch requestMessages[idx] {
            case let .user(content, _):
                rolePrefix = "user"
                firstLine = firstNonEmptyLine(of: content)
            case let .assistant(content, _, _):
                rolePrefix = "assistant"
                firstLine = content.map(firstNonEmptyLine(of:)) ?? ""
            case let .system(content, _):
                rolePrefix = "system"
                firstLine = firstNonEmptyLine(of: content)
            case let .tool(content, _):
                rolePrefix = "tool"
                firstLine = firstNonEmptyLine(of: content)
            case let .developer(content, _):
                rolePrefix = "developer"
                firstLine = firstNonEmptyLine(of: content)
            }

            guard !firstLine.isEmpty else { continue }
            let line = "\(rolePrefix): \(firstLine)"
            let lineTokens = ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: [.system(content: .text(line))],
                tools: [],
            )
            guard summaryTokenCount + lineTokens <= summaryBudget else { continue }
            summaryLines.append(line)
            summaryTokenCount += lineTokens
        }

        // Phase 3: Replace — remove evicted messages then insert summary after system messages
        for idx in indicesToEvict.reversed() {
            requestMessages.remove(at: idx)
        }

        if !summaryLines.isEmpty {
            let summaryText = "The following messages were summarized due to context length limits:\n"
                + summaryLines.joined(separator: "\n")
            let summaryMessage = ChatRequestBody.Message.system(content: .text(summaryText))

            // Check that adding summary won't push us back over the limit
            let postEvictTokens = ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: requestMessages,
                tools: tools ?? [],
            )
            let summaryTokens = ModelManager.shared.calculateEstimateTokensUsingCommonEncoder(
                input: [summaryMessage],
                tools: [],
            )
            if postEvictTokens + summaryTokens <= modelContextLength {
                // Insert summary after the last existing system message (or at index 0 if none)
                let insertionIndex = requestMessages.lastIndex(where: {
                    if case .system = $0 { return true }
                    return false
                }).map { $0 + 1 } ?? 0

                requestMessages.insert(summaryMessage, at: insertionIndex)
            } else {
                Logger.model.debugFile("skipping summary insertion: would exceed context length (\(postEvictTokens + summaryTokens) > \(modelContextLength))")
            }
        }

        return true
    }

    /// Text-only messages carry either a single string or a list of strings.
    private func firstNonEmptyLine(of content: ChatRequestBody.MessageContent<String, [String]>) -> String {
        switch content {
        case let .text(text): firstNonEmptyLine(text)
        case let .parts(parts): firstNonEmptyLine(parts.joined(separator: "\n"))
        }
    }

    /// User messages are multimodal: only the first text part carries a line.
    private func firstNonEmptyLine(of content: ChatRequestBody.MessageContent<String, [ChatRequestBody.ContentPart]>) -> String {
        switch content {
        case let .text(text):
            firstNonEmptyLine(text)
        case let .parts(parts):
            firstNonEmptyLine(parts.compactMap { part -> String? in
                if case let .text(partText) = part { return partText }
                return nil
            }.first ?? "")
        }
    }

    private func firstNonEmptyLine(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first(where: { !$0.isEmpty }) ?? ""
    }
}

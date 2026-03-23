//
//  MemoryExtractor.swift
//  FlowDown
//
//  Created by Alan Ye on 3/23/26.
//

import ChatClientKit
import Foundation
import Storage

@MainActor
final class MemoryExtractor {
    static let shared = MemoryExtractor()

    private var lastExtraction: [String: Date] = [:]
    private let cooldown: TimeInterval = 300

    private init() {}

    // MARK: - Public Entry Point

    func extractIfNeeded(
        from messages: [Message],
        conversationId: String,
        using modelId: ModelManager.ModelIdentifier?
    ) async {
        guard let modelId else {
            Logger.model.debugFile("MemoryExtractor skipping: no model selected")
            return
        }

        let relevant = messages.filter { $0.role == .user || $0.role == .assistant }
        guard relevant.count > 2 else {
            Logger.model.debugFile("MemoryExtractor skipping: insufficient message pairs")
            return
        }

        if let last = lastExtraction[conversationId],
           Date().timeIntervalSince(last) < cooldown
        {
            Logger.model.debugFile("MemoryExtractor skipping: cooldown not elapsed for conversation \(conversationId)")
            return
        }

        lastExtraction[conversationId] = Date()

        let snippet = buildRecentSnippet(from: messages)

        do {
            let facts = try await extractFacts(from: snippet, using: modelId)
            guard !facts.isEmpty else {
                Logger.model.debugFile("MemoryExtractor: no facts extracted")
                return
            }

            let newFacts = await deduplicateFacts(facts)
            guard !newFacts.isEmpty else {
                Logger.model.debugFile("MemoryExtractor: all facts were duplicates")
                return
            }

            for fact in newFacts {
                MemoryStore.shared.store(content: fact, conversationId: conversationId)
            }
            Logger.model.infoFile("MemoryExtractor: stored \(newFacts.count) new fact(s) for conversation \(conversationId)")
        } catch {
            Logger.model.errorFile("MemoryExtractor: extraction failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func buildRecentSnippet(from messages: [Message]) -> String {
        let relevant = messages.filter { $0.role == .user || $0.role == .assistant }
        let recent = relevant.suffix(6)

        return recent.map { msg in
            let role = msg.role == .user ? "User" : "Assistant"
            let text = String(msg.document.prefix(1000))
            return "\(role): \(text)"
        }.joined(separator: "\n")
    }

    private func extractFacts(from snippet: String, using modelId: ModelManager.ModelIdentifier) async throws -> [String] {
        let systemPrompt = """
        You are a memory extraction assistant. Analyze the following conversation snippet and extract up to 5 persistent, personally relevant facts about the user.

        Rules:
        - Write facts in third person (e.g., "User is a software engineer", "User prefers dark mode").
        - Only extract persistent, meaningful information such as preferences, goals, personal details, or important context.
        - Do NOT extract transient or trivial information.
        - Output ONLY a JSON array of strings. Do not include any explanation or additional text.
        - Example output: ["User prefers concise responses.", "User is learning Swift."]
        - If no relevant facts are found, output an empty array: []
        """

        let messages: [ChatRequestBody.Message] = [
            .system(content: .text(systemPrompt)),
            .user(content: .text("Conversation:\n\(snippet)\n\nExtract facts as a JSON array:")),
        ]

        let response = try await ModelManager.shared.infer(
            with: modelId,
            maxCompletionTokens: 512,
            input: messages
        )

        let responseText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return parseJSONArray(from: responseText)
    }

    private func parseJSONArray(from text: String) -> [String] {
        // Find the first '[' and last ']' to handle surrounding text
        guard let startIndex = text.firstIndex(of: "["),
              let endIndex = text.lastIndex(of: "]"),
              startIndex <= endIndex
        else {
            Logger.model.debugFile("MemoryExtractor: could not find JSON array in response")
            return []
        }

        let jsonSubstring = String(text[startIndex ... endIndex])

        guard let data = jsonSubstring.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [String]
        else {
            Logger.model.debugFile("MemoryExtractor: failed to parse JSON array from: \(jsonSubstring)")
            return []
        }

        return array.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func deduplicateFacts(_ candidates: [String]) async -> [String] {
        let existingMemories: [Memory]
        do {
            existingMemories = try await MemoryStore.shared.getAllMemoriesAsync()
        } catch {
            Logger.model.errorFile("MemoryExtractor: failed to load existing memories for deduplication: \(error.localizedDescription)")
            return candidates
        }

        let existingContents = existingMemories.map(\.content)

        return candidates.filter { candidate in
            let candidateWords = wordSet(candidate)
            for existing in existingContents {
                let existingWords = wordSet(existing)
                let intersection = candidateWords.intersection(existingWords)
                let union = candidateWords.union(existingWords)
                guard !union.isEmpty else { continue }
                let jaccard = Double(intersection.count) / Double(union.count)
                if jaccard > 0.7 {
                    Logger.model.debugFile("MemoryExtractor: deduplicating '\(candidate)' (Jaccard \(String(format: "%.2f", jaccard)) with '\(existing)')")
                    return false
                }
            }
            return true
        }
    }

    private func wordSet(_ text: String) -> Set<String> {
        let lowercased = text.lowercased()
        let words = lowercased.components(separatedBy: .alphanumerics.inverted)
        return Set(words.filter { !$0.isEmpty })
    }
}

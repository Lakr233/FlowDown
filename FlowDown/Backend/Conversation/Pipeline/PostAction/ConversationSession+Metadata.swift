//
//  ConversationSession+Metadata.swift
//  FlowDown
//
//  Created by Codex on 4/12/26.
//

import ChatClientKit
import Foundation
import Storage

struct ConversationMetadata: Equatable {
    let title: String?
    let icon: String?

    var hasGeneratedContent: Bool {
        title != nil || icon != nil
    }
}

enum ConversationMetadataToolCall {
    static let name = "save_conversation_metadata"

    static var definition: ChatRequestBody.Tool {
        .function(
            name: name,
            description: "Save the generated title and icon for the conversation.",
            parameters: [
                "type": "object",
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "A concise 3-5 word title summarizing the conversation, in the user's primary language, without any prefix, label, or markdown.",
                    ],
                    "icon": [
                        "type": "string",
                        "description": "A single emoji character that best represents the conversation.",
                    ],
                ],
                "required": ["title", "icon"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    private struct Arguments: Decodable {
        let title: String?
        let icon: String?
    }

    static func parse(arguments: String) -> ConversationMetadata? {
        guard let data = arguments.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Arguments.self, from: data)
        else {
            return nil
        }

        let metadata = ConversationMetadata(
            title: normalizedTitle(decoded.title),
            icon: normalizedIcon(decoded.icon),
        )

        return metadata.hasGeneratedContent ? metadata : nil
    }

    static func normalizedTitle(_ title: String?) -> String? {
        guard let title else { return nil }

        var normalized = title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingMarkdownBold()

        guard !normalized.isEmpty else { return nil }
        if normalized.count > 32 {
            normalized = String(normalized.prefix(32))
        }
        return normalized
    }

    static func normalizedIcon(_ icon: String?) -> String? {
        guard let icon else { return nil }

        let normalized = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        guard normalized.count == 1 else {
            let firstEmoji = normalized.first { $0.isEmoji }
            return firstEmoji.map(String.init)
        }

        return normalized
    }
}

extension ConversationManager {
    /// Writes generated metadata onto the stored conversation. Automatic renames
    /// also clear `shouldAutoRename` so a generated title is only ever chosen once.
    func applyMetadata(
        _ metadata: ConversationMetadata,
        to identifier: Conversation.ID,
        disablingAutoRename: Bool,
    ) {
        editConversation(identifier: identifier) {
            if let title = metadata.title {
                $0.update(\.title, to: title)
            }
            if let icon = metadata.icon {
                let iconData = icon.textToImage(size: 128)?.pngData() ?? .init()
                $0.update(\.icon, to: iconData)
            }
            if disablingAutoRename {
                $0.update(\.shouldAutoRename, to: false)
            }
        }
    }
}

extension ConversationSessionManager.Session {
    func generateConversationMetadata() async -> ConversationMetadata? {
        guard let userMessage = messages.last(where: { $0.role == .user })?.document else {
            return nil
        }
        guard let assistantMessage = messages.last(where: { $0.role == .assistant })?.document else {
            return nil
        }

        guard let model = models.auxiliary else { return nil }

        if ModelManager.shared.modelCapabilities(identifier: model).contains(.tool),
           let metadata = await generateMetadataWithToolCall(
               model: model,
               userMessage: userMessage,
               assistantMessage: assistantMessage,
           ) {
            return metadata
        }

        // Not every auxiliary endpoint answers a forced tool call — plain chat
        // models and proxy endpoints without tool support among them. A plain
        // completion still produces a title, so fall back instead of skipping.
        Logger.model.infoFile("conversation metadata generation: using plain-text fallback")
        return await generateMetadataWithPlainText(
            model: model,
            userMessage: userMessage,
            assistantMessage: assistantMessage,
        )
    }

    private func generateMetadataWithToolCall(
        model: ModelManager.ModelIdentifier,
        userMessage: String,
        assistantMessage: String,
    ) async -> ConversationMetadata? {
        let input: [ChatRequestBody.Message] = [
            .system(content: .text(
                "Generate metadata for the conversation. You must call \(ConversationMetadataToolCall.name) exactly once with a title and an icon. Do not respond with plain text.",
            )),
            .user(content: .text(
                """
                [last user message]
                \(userMessage)

                [last assistant message]
                \(assistantMessage)
                """,
            )),
        ]

        do {
            let response = try await ModelManager.shared.infer(
                with: model,
                input: input,
                tools: [ConversationMetadataToolCall.definition],
                toolChoice: .function(name: ConversationMetadataToolCall.name),
            )

            guard let call = response.tools.first(where: { $0.name == ConversationMetadataToolCall.name }) else {
                Logger.model.errorFile("conversation metadata generation returned no tool call")
                return nil
            }

            return ConversationMetadataToolCall.parse(arguments: call.args)
        } catch {
            Logger.model.errorFile("failed to generate conversation metadata: \(error)")
            return nil
        }
    }

    private func generateMetadataWithPlainText(
        model: ModelManager.ModelIdentifier,
        userMessage: String,
        assistantMessage: String,
    ) async -> ConversationMetadata? {
        let input: [ChatRequestBody.Message] = [
            .system(content: .text(
                """
                Generate metadata for the conversation. Respond with ONLY one JSON object in this exact shape, with no markdown, code fence, or commentary:
                {"title": "3-5 word title in the user's primary language, no prefix, label, or markdown", "icon": "a single emoji"}
                """,
            )),
            .user(content: .text(
                """
                [last user message]
                \(userMessage)

                [last assistant message]
                \(assistantMessage)
                """,
            )),
        ]

        do {
            let response = try await ModelManager.shared.infer(with: model, input: input)
            return ConversationMetadataPlainTextParser.parse(response.text)
        } catch {
            Logger.model.errorFile("failed to generate conversation metadata (plain text): \(error)")
            return nil
        }
    }
}

/// Reads a title and an icon out of a plain completion. Models without tool
/// support format their answer however they please, so this tries a JSON
/// object first, then `title:` / `icon:` lines, and finally takes the first
/// line as the title.
enum ConversationMetadataPlainTextParser {
    private struct PlainArguments: Decodable {
        let title: String?
        let icon: String?
    }

    static func parse(_ response: String) -> ConversationMetadata? {
        if let metadata = parseJSONObject(in: response) { return metadata }
        if let metadata = parseLabeledLines(in: response) { return metadata }
        return parseFirstLine(in: response)
    }

    private static func parseJSONObject(in response: String) -> ConversationMetadata? {
        guard let start = response.firstIndex(of: "{"),
              let end = response.lastIndex(of: "}"),
              start < end,
              let data = response[start ... end].data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PlainArguments.self, from: data)
        else {
            return nil
        }

        let metadata = ConversationMetadata(
            title: ConversationMetadataToolCall.normalizedTitle(decoded.title),
            icon: ConversationMetadataToolCall.normalizedIcon(decoded.icon),
        )
        return metadata.hasGeneratedContent ? metadata : nil
    }

    private static func parseLabeledLines(in response: String) -> ConversationMetadata? {
        var title: String?
        var icon: String?

        for rawLine in response.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { continue }

            let quoteAndSpace = CharacterSet.whitespacesAndNewlines.union(.init(charactersIn: "\"'`"))
            let key = line[..<colon].trimmingCharacters(in: quoteAndSpace)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: quoteAndSpace)

            switch key.lowercased() {
            case "title", "标题": title = value
            case "icon", "emoji", "图标": icon = value
            default: break
            }
        }

        guard title != nil || icon != nil else { return nil }

        let metadata = ConversationMetadata(
            title: ConversationMetadataToolCall.normalizedTitle(title),
            icon: ConversationMetadataToolCall.normalizedIcon(icon),
        )
        return metadata.hasGeneratedContent ? metadata : nil
    }

    private static func parseFirstLine(in response: String) -> ConversationMetadata? {
        let line = response.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let line else { return nil }

        let metadata = ConversationMetadata(
            title: ConversationMetadataToolCall.normalizedTitle(line),
            icon: nil,
        )
        return metadata.hasGeneratedContent ? metadata : nil
    }
}

private extension String {
    func trimmingMarkdownBold() -> String {
        var result = self
        if result.hasPrefix("**"), result.hasSuffix("**"), result.count > 4 {
            result = String(result.dropFirst(2).dropLast(2))
        }
        return result
    }
}

private extension Character {
    var isEmoji: Bool {
        guard let scalar = unicodeScalars.first else { return false }
        return scalar.properties.isEmoji &&
            (scalar.value > 0x238C || unicodeScalars.count > 1)
    }
}

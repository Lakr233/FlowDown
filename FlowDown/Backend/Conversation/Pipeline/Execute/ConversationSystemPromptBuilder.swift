//
//  ConversationSystemPromptBuilder.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 4/12/26.
//

import ChatClientKit
import Foundation

/// Adds the per-request prompt parts around the stored history.
///
/// Providers cache a request by its prefix, so the parts are ordered by how
/// often they change:
///
/// 1. Fixed: the stored system prompt (already in history), then the tool
///    guidance, which depends only on settings. It goes right after the
///    leading system messages, ahead of the history.
/// 2. Variable: runtime info (model name, day-precision date, locale),
///    proactive memory, recent conversations and the web search mode. They
///    travel as a `<context>` block leading the current user message's
///    text, which is never stored, so the history replays byte-identical
///    next turn.
///
/// Apple Intelligence rebuilds its session for every request and folds all
/// system messages into its instructions, so it gets the variable parts as
/// system messages instead (``ContextPlacement/systemMessages``).
enum ConversationSystemPromptBuilder {
    enum ContextPlacement {
        /// Leading block of the final user message's text.
        case finalUserMessage
        /// Separate system messages after the fixed ones.
        case systemMessages
    }

    static func contextPlacement(for modelID: ModelManager.ModelIdentifier) -> ContextPlacement {
        if #available(iOS 26.0, macCatalyst 26.0, *), modelID == AppleIntelligenceModel.shared.modelIdentifier {
            return .systemMessages
        }
        return .finalUserMessage
    }

    struct Input {
        let userText: String
        let modelName: String
        let modelWillExecuteTools: Bool
        let webSearchEnabled: Bool
        var contextPlacement: ContextPlacement = .finalUserMessage
    }

    struct Dependencies {
        let enabledTools: [any ModelTool]
        let proactiveMemoryScope: MemoryProactiveProvisionScope
        let searchSensitivity: ModelManager.SearchSensitivity
        let runtimeSystemInfoProvider: ((String) -> String)?
        let proactiveMemoryContextProvider: () async -> String?
        let recentConversationContextProvider: (_ limit: Int) async -> String?

        static func live() -> Dependencies {
            .init(
                enabledTools: ModelToolsManager.shared.enabledTools.map { $0 as any ModelTool },
                proactiveMemoryScope: MemoryProactiveProvisionSetting.currentScope,
                searchSensitivity: ModelManager.shared.searchSensitivity,
                runtimeSystemInfoProvider: ModelManager.shared.includeDynamicSystemInfo ? { modelName in
                    runtimeSystemInfo(modelName: modelName, date: Date().promptDay())
                } : nil,
                proactiveMemoryContextProvider: {
                    await MemoryStore.shared.formattedProactiveMemoryContext()
                },
                recentConversationContextProvider: { limit in
                    await ConversationSummarizer.shared.formattedRecentSummaries(limit: limit)
                },
            )
        }
    }

    static func runtimeSystemInfo(modelName: String, date: String) -> String {
        String(localized:
            """
            Current context:
            Your Name: \(modelName)
            Date: \(date)
            User Locale: \(Locale.current.identifier)
            """)
    }

    static let contextSectionOpening = "<context>"
    static let contextSectionClosing = "</context>"

    static func appendMessages(
        to requestMessages: inout [ChatRequestBody.Message],
        input: Input,
        dependencies: Dependencies,
    ) async {
        let shouldExposeMemory = ModelToolsManager.shouldExposeMemory(
            modelWillExecuteTools: input.modelWillExecuteTools,
            enabledTools: dependencies.enabledTools,
        )

        // Fixed parts.
        var fixedBlocks: [String] = []
        if input.modelWillExecuteTools {
            fixedBlocks.append(toolGuidance(
                includesMemoryTools: shouldExposeMemory,
                proactiveMemoryProvided: false,
            ))
        }

        // Variable parts.
        var contextBlocks: [String] = []

        if let runtimeSystemInfoProvider = dependencies.runtimeSystemInfoProvider {
            let runtimeContent = runtimeSystemInfoProvider(input.modelName)
            if !runtimeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                contextBlocks.append(runtimeContent)
            }
        }

        let shouldInjectCrossConversationContext =
            MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(
                for: dependencies.proactiveMemoryScope,
            )

        if shouldExposeMemory,
           shouldInjectCrossConversationContext,
           let proactiveMemoryContext = await dependencies.proactiveMemoryContextProvider(),
           !proactiveMemoryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            // The note refers to the summary "above", so it follows it here
            // rather than the fixed tool guidance.
            contextBlocks.append(proactiveMemoryContext + "\n\n" + proactiveMemoryNote)
        }

        if shouldInjectCrossConversationContext,
           let recentConversationContext = await dependencies.recentConversationContextProvider(15),
           !recentConversationContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            contextBlocks.append(recentConversationContext)
        }

        if input.webSearchEnabled {
            let sensitivity = dependencies.searchSensitivity
            let sensitivityTitle = String(localized: sensitivity.title)
            contextBlocks.append(
                """
                Web Search Mode: \(sensitivityTitle)
                \(sensitivity.briefDescription)
                """,
            )
        }

        var systemMessages = fixedBlocks.map { ChatRequestBody.Message.system(content: .text($0)) }
        let userMessage: ChatRequestBody.Message
        switch input.contextPlacement {
        case .systemMessages:
            systemMessages += contextBlocks.map { .system(content: .text($0)) }
            userMessage = .user(content: .text(input.userText))
        case .finalUserMessage:
            // Attachments travel as their own messages before this one, so
            // the final message is text only. A single string keeps it
            // acceptable to servers that reject array content for text.
            if contextBlocks.isEmpty {
                userMessage = .user(content: .text(input.userText))
            } else {
                userMessage = .user(content: .text(
                    contextSection(contextBlocks) + "\n\n" + input.userText,
                ))
            }
        }

        let leadingSystemCount = requestMessages.prefix { message in
            if case .system = message { return true }
            return false
        }.count
        requestMessages.insert(contentsOf: systemMessages, at: leadingSystemCount)
        requestMessages.append(userMessage)
    }

    static func contextSection(_ blocks: [String]) -> String {
        [
            contextSectionOpening,
            blocks.joined(separator: "\n\n"),
            contextSectionClosing,
        ].joined(separator: "\n")
    }

    static func toolGuidance(includesMemoryTools: Bool, proactiveMemoryProvided: Bool) -> String {
        var guidance = String(localized:
            """
            Use the provided tools when they fit the user's request. Don't look up what is already given or easily inferred.
            """)

        if includesMemoryTools {
            guidance += "\n\n" + MemoryStore.memoryToolsPrompt
        }

        if proactiveMemoryProvided {
            guidance += "\n\n" + proactiveMemoryNote
        }

        return guidance
    }

    static var proactiveMemoryNote: String {
        String(localized: "The memory summary above follows the user's settings. Treat it as reliable and keep it current with the memory tools.")
    }
}

//
//  ConversationSystemPromptBuilder.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 4/12/26.
//

import ChatClientKit
import Foundation

enum ConversationSystemPromptBuilder {
    struct Input {
        let userText: String
        let modelName: String
        let modelWillExecuteTools: Bool
        let webSearchEnabled: Bool
    }

    struct Dependencies {
        let enabledTools: [ModelTool]
        let proactiveMemoryScope: MemoryProactiveProvisionScope
        let searchSensitivity: ModelManager.SearchSensitivity
        /// Cleared when the user opts out of dynamic system info.
        var runtimeSystemInfoProvider: ((String) -> String)?
        let proactiveMemoryContextProvider: () async -> String?
        let recentConversationContextProvider: (_ limit: Int) async -> String?

        static func live() -> Dependencies {
            .init(
                enabledTools: ModelToolsManager.shared.enabledTools,
                proactiveMemoryScope: MemoryProactiveProvisionSetting.currentScope,
                searchSensitivity: ModelManager.shared.searchSensitivity,
                runtimeSystemInfoProvider: { modelName in
                    String(localized:
                        """
                        Current context:
                        Your Name: \(modelName)
                        Date: \(Date().promptTimestamp)
                        User Locale: \(Locale.current.identifier)
                        """)
                },
                proactiveMemoryContextProvider: {
                    await MemoryStore.shared.formattedProactiveMemoryContext()
                },
                recentConversationContextProvider: { limit in
                    await ConversationSummarizer.shared.formattedRecentSummaries(limit: limit)
                },
            )
        }
    }

    static func appendMessages(
        to requestMessages: inout [ChatRequestBody.Message],
        input: Input,
        dependencies: Dependencies,
    ) async {
        var proactiveMemoryProvided = false

        if let runtimeSystemInfoProvider = dependencies.runtimeSystemInfoProvider {
            let runtimeContent = runtimeSystemInfoProvider(input.modelName)
            if !runtimeContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                requestMessages.append(.system(content: .text(runtimeContent)))
            }
        }

        let shouldExposeMemory = ModelToolsManager.shouldExposeMemory(
            modelWillExecuteTools: input.modelWillExecuteTools,
            enabledTools: dependencies.enabledTools,
        )

        let shouldInjectCrossConversationContext = MemoryProactiveProvisionSetting.shouldInjectRecentConversationContext(
            for: dependencies.proactiveMemoryScope,
        )

        if shouldExposeMemory,
           shouldInjectCrossConversationContext,
           let proactiveMemoryContext = await dependencies.proactiveMemoryContextProvider(),
           !proactiveMemoryContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            requestMessages.append(.system(content: .text(proactiveMemoryContext)))
            proactiveMemoryProvided = true
        }

        if shouldInjectCrossConversationContext,
           let recentConversationContext = await dependencies.recentConversationContextProvider(15),
           !recentConversationContext.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            requestMessages.append(.system(content: .text(recentConversationContext)))
        }

        if input.webSearchEnabled {
            let sensitivity = dependencies.searchSensitivity
            let sensitivityTitle = String(localized: sensitivity.title)
            requestMessages.append(
                .system(
                    content: .text(
                        """
                        Web Search Mode: \(sensitivityTitle)
                        \(sensitivity.briefDescription)
                        """,
                    ),
                ),
            )
        }

        if input.modelWillExecuteTools {
            var toolGuidance = String(localized:
                """
                Use the provided tools when they fit the user's request. Don't look up what is already given or easily inferred.
                """)

            if shouldExposeMemory {
                toolGuidance += "\n\n" + MemoryStore.memoryToolsPrompt
            }

            if proactiveMemoryProvided {
                toolGuidance += "\n\n" +
                    String(localized: "The memory summary above follows the user's settings. Treat it as reliable and keep it current with the memory tools.")
            }

            requestMessages.append(.system(content: .text(toolGuidance)))
        }

        requestMessages.append(.user(content: .text(input.userText)))
    }
}

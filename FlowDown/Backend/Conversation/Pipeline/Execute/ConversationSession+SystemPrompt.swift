//
//  ConversationSession+SystemPrompt.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation

extension ConversationSession {
    func injectNewSystemCommand(
        _ requestMessages: inout [ChatRequestBody.Message],
        _ modelName: String,
        _ modelWillExecuteTools: Bool,
        _ webSearchEnabled: Bool,
        _ object: RichEditorView.Object,
    ) async {
        let liveDependencies = ConversationSystemPromptBuilder.Dependencies.live()
        let dependencies = ConversationSystemPromptBuilder.Dependencies(
            enabledTools: liveDependencies.enabledTools,
            proactiveMemoryScope: liveDependencies.proactiveMemoryScope,
            searchSensitivity: liveDependencies.searchSensitivity,
            runtimeSystemInfoProvider: ModelManager.shared.includeDynamicSystemInfo
                ? liveDependencies.runtimeSystemInfoProvider
                : nil,
            proactiveMemoryContextProvider: liveDependencies.proactiveMemoryContextProvider,
            recentConversationContextProvider: liveDependencies.recentConversationContextProvider,
        )

        let input = ConversationSystemPromptBuilder.Input(
            userText: object.text,
            modelName: modelName,
            modelWillExecuteTools: modelWillExecuteTools,
            webSearchEnabled: webSearchEnabled,
        )

        await ConversationSystemPromptBuilder.appendMessages(
            to: &requestMessages,
            input: input,
            dependencies: dependencies,
        )
    }
}

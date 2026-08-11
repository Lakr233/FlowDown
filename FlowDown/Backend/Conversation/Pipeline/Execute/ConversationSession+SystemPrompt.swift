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
        var dependencies = ConversationSystemPromptBuilder.Dependencies.live()
        if !ModelManager.shared.includeDynamicSystemInfo {
            dependencies.runtimeSystemInfoProvider = nil
        }

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

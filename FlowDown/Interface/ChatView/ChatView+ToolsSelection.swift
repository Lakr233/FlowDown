//
//  ChatView+ToolsSelection.swift
//  FlowDown
//

import Storage
import UIKit

/// Decisions behind the composer's Tools menu, kept apart from UIKit so they can be tested.
enum ToolsSelectionPolicy {
    /// The general Tools toggle after the user changes which tools are selected.
    ///
    /// Picking a tool (an MCP server or a built-in one) means the user wants tools,
    /// so a toggle left off turns on, but only for a model that can call tools.
    /// Deselecting never turns it off.
    static func toolsEnabledAfterSelection(
        selectionTurnedOn: Bool,
        toolsEnabled: Bool,
        modelSupportsTools: Bool,
    ) -> Bool {
        if toolsEnabled { return true }
        return selectionTurnedOn && modelSupportsTools
    }

    /// Whether to tell the user that the tool change affects the next reply.
    ///
    /// The tools offered to the model are part of the request prefix the provider
    /// caches, so changing them in a conversation that already has messages makes
    /// the next reply start without that cache. Changes that leave the offered
    /// tools as they were (selecting while the toggle stays off) say nothing.
    static func shouldHintToolsChange(
        toolsEnabledBefore: Bool,
        toolsEnabledAfter: Bool,
        selectionChanged: Bool,
        conversationHasMessages: Bool,
    ) -> Bool {
        guard conversationHasMessages else { return false }
        if toolsEnabledBefore != toolsEnabledAfter { return true }
        return toolsEnabledAfter && selectionChanged
    }

    /// Whether the conversation has anything the model has already been sent.
    static func conversationHasMessages(_ messages: [Message]) -> Bool {
        messages.contains { $0.role == .user || $0.role == .assistant }
    }
}

extension ChatView {
    static var toolsChangedHintText: String {
        String(localized: "Tools changed. The next reply may take a little longer.")
    }

    private var toolsToggleIsOn: Bool {
        editor.quickSettingBar.toolsToggle.isOn
    }

    /// Flips the general Tools toggle from the menu.
    func applyToolsToggleChange(requestReload: (Bool) -> Void) {
        let before = toolsToggleIsOn
        requestReload(!before)
        noteToolsChange(toolsEnabledBefore: before, selectionChanged: false)
    }

    /// Applies a tool selection made from the menu. `change` updates the
    /// selection and returns whether it turned something on.
    func applyToolSelectionChange(
        requestReload: (Bool) -> Void,
        change: () -> Bool,
    ) {
        // Read the toggle now: the menu stays open between picks, so the value
        // it was built with can be stale.
        let before = toolsToggleIsOn
        let turnedOn = change()
        let modelSupportsTools = modelIdentifier().map {
            onRichEditorCheckIfModelSupportsToolCall($0)
        } ?? false
        requestReload(ToolsSelectionPolicy.toolsEnabledAfterSelection(
            selectionTurnedOn: turnedOn,
            toolsEnabled: before,
            modelSupportsTools: modelSupportsTools,
        ))
        noteToolsChange(toolsEnabledBefore: before, selectionChanged: true)
    }

    private func noteToolsChange(toolsEnabledBefore: Bool, selectionChanged: Bool) {
        guard let conversationIdentifier else { return }
        let messages = ConversationSessionManager.shared.session(for: conversationIdentifier).messages
        guard ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: toolsEnabledBefore,
            toolsEnabledAfter: toolsToggleIsOn,
            selectionChanged: selectionChanged,
            conversationHasMessages: ToolsSelectionPolicy.conversationHasMessages(messages),
        ) else { return }
        editor.showToolsChangeHint(Self.toolsChangedHintText)
    }
}

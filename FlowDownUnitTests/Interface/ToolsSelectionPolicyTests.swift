//
//  ToolsSelectionPolicyTests.swift
//  FlowDownUnitTests
//

import Combine
@testable import FlowDown
import Foundation
import Storage
import Testing
import UIKit

struct ToolsSelectionPolicyTests {
    @Test
    func selectingTool_toolsOff_modelSupportsTools_turnsToolsOn() {
        #expect(ToolsSelectionPolicy.toolsEnabledAfterSelection(
            selectionTurnedOn: true,
            toolsEnabled: false,
            modelSupportsTools: true,
        ))
    }

    @Test
    func selectingTool_modelWithoutTools_leavesToolsOff() {
        #expect(!ToolsSelectionPolicy.toolsEnabledAfterSelection(
            selectionTurnedOn: true,
            toolsEnabled: false,
            modelSupportsTools: false,
        ))
    }

    @Test
    func deselectingTool_neverChangesToggle() {
        #expect(!ToolsSelectionPolicy.toolsEnabledAfterSelection(
            selectionTurnedOn: false,
            toolsEnabled: false,
            modelSupportsTools: true,
        ))
        #expect(ToolsSelectionPolicy.toolsEnabledAfterSelection(
            selectionTurnedOn: false,
            toolsEnabled: true,
            modelSupportsTools: true,
        ))
    }

    @Test
    func toolsChangeHint_onlyWhenOfferedToolsChangeInStartedConversation() {
        // Empty conversation: nothing cached yet.
        #expect(!ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: false,
            toolsEnabledAfter: true,
            selectionChanged: true,
            conversationHasMessages: false,
        ))
        // Auto-enable or the toggle itself.
        #expect(ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: false,
            toolsEnabledAfter: true,
            selectionChanged: true,
            conversationHasMessages: true,
        ))
        #expect(ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: true,
            toolsEnabledAfter: false,
            selectionChanged: false,
            conversationHasMessages: true,
        ))
        // A selection change while tools are on.
        #expect(ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: true,
            toolsEnabledAfter: true,
            selectionChanged: true,
            conversationHasMessages: true,
        ))
        // A selection change while tools stay off sends nothing new.
        #expect(!ToolsSelectionPolicy.shouldHintToolsChange(
            toolsEnabledBefore: false,
            toolsEnabledAfter: false,
            selectionChanged: true,
            conversationHasMessages: true,
        ))
    }

    @Test
    func conversationHasMessages_ignoresNonChatRows() {
        let system = Message(deviceId: "ToolsSelectionPolicyTests")
        system.update(\.role, to: .system)
        let hint = Message(deviceId: "ToolsSelectionPolicyTests")
        hint.update(\.role, to: .hint)
        #expect(!ToolsSelectionPolicy.conversationHasMessages([]))
        #expect(!ToolsSelectionPolicy.conversationHasMessages([system, hint]))

        let user = Message(deviceId: "ToolsSelectionPolicyTests")
        user.update(\.role, to: .user)
        #expect(ToolsSelectionPolicy.conversationHasMessages([system, user]))
    }

    @MainActor
    @Test
    func richEditorToolsChangeHint_showsUntilEditorResets() {
        let editor = RichEditorView()
        #expect(!editor.toolsChangeHint.isActive)
        #expect(editor.toolsChangeHint.heightPublisher.value == 0)

        editor.showToolsChangeHint(ChatView.toolsChangedHintText)
        #expect(editor.toolsChangeHint.isActive)
        #expect(editor.toolsChangeHint.label.text == ChatView.toolsChangedHintText)
        #expect(editor.toolsChangeHint.heightPublisher.value > 0)
        // It is a note, not a block: sending stays possible.
        #expect(editor.inputEditor.sendButton.isEnabled == !editor.visualInputHint.isActive)

        editor.resetValues()
        #expect(!editor.toolsChangeHint.isActive)
        #expect(editor.toolsChangeHint.heightPublisher.value == 0)
    }
}

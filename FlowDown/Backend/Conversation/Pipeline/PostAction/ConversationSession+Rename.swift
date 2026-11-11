//
//  ConversationSession+Rename.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationSession {
    /// Names the conversation after a turn. Until then it shows the first
    /// message, set when the user sent it. A generated title replaces that;
    /// when none can be generated (the model cannot call tools, the provider
    /// failed, or the reply was not a usable tool call) the first message
    /// stays. Either way auto-rename then turns off, so a failing model is not
    /// asked again after every turn; Generate New Title stays available.
    func updateTitleAndIcon() async {
        if let metadata = await generateConversationMetadata() {
            // An icon alone leaves the title to the fallback.
            if metadata.title == nil { applyFallbackTitleIfNeeded() }
            ConversationManager.shared.applyMetadata(metadata, to: id, isAutomatic: true)
            return
        }
        // With only attachments sent so far, try again after the next turn.
        guard let title = firstMessageTitle() else { return }
        Logger.model.infoFile("conversation title not generated; keeping the first user message")
        ConversationManager.shared.applyFallbackTitle(title, to: id)
        if shouldAutoRename { shouldAutoRename = false }
    }
}

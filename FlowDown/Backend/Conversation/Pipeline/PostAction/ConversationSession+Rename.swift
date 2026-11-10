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
    /// Names the conversation after a turn. When no title can be generated
    /// (the model cannot call tools, the provider failed, or the reply was not
    /// a usable tool call) the user's first message becomes the title instead.
    /// Either way auto-rename then turns off, so a failing model is not asked
    /// again after every turn; Generate New Title stays available for that.
    func updateTitleAndIcon() async {
        if let metadata = await generateConversationMetadata() {
            ConversationManager.shared.applyMetadata(metadata, to: id, disablingAutoRename: true)
            return
        }
        // With only attachments sent so far, try again after the next turn.
        guard let fallback = fallbackConversationMetadata() else { return }
        Logger.model.infoFile("conversation title not generated; using the first user message")
        ConversationManager.shared.applyMetadata(fallback, to: id, disablingAutoRename: true)
    }
}

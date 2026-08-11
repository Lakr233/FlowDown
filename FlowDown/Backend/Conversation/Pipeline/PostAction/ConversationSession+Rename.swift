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
    func updateTitleAndIcon() async {
        guard let metadata = await generateConversationMetadata() else { return }
        ConversationManager.shared.applyMetadata(metadata, to: id, disablingAutoRename: true)
    }
}

//
//  Sidebar+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import Foundation
import Storage
import UIKit

extension Sidebar: NewChatButton.Delegate {
    func newChatDidCreated(_ identifier: Conversation.ID) {
        ChatSelection.shared.select(identifier, options: [.collapseSidebar, .focusEditor])
    }
}

extension Sidebar: SearchControllerOpenButton.Delegate {
    func searchButtonDidTap() {
        let controller = ConversationSearchController { conversationId in
            Logger.ui.debugFile("Search callback called with conversationId: \(conversationId ?? "nil")")
            guard let conversationId else { return }
            Logger.ui.debugFile("Setting chat selection to: \(conversationId)")
            ChatSelection.shared.select(conversationId, options: [.collapseSidebar])
        }
        parentViewController?.present(controller, animated: true)
    }
}

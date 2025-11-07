//
//  ChatSelection.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/10/31.
//

import Combine
import Foundation
import Storage

class ChatSelection {
    struct Options: OptionSet {
        let rawValue: Int

        static let collapseSidebar = Options(rawValue: 1 << 0)
        static let focusEditor = Options(rawValue: 1 << 1)

        static let none: Options = []
    }

    enum Selection: Equatable {
        case none
        case conversation(id: Conversation.ID, options: Options = .none)

        var identifier: Conversation.ID? {
            switch self {
            case .none:
                nil
            case let .conversation(id, _):
                id
            }
        }

        var options: Options {
            switch self {
            case .none:
                .none
            case let .conversation(_, options):
                options
            }
        }
    }

    static let shared = ChatSelection()

    private let subject = CurrentValueSubject<Selection, Never>(.none)
    let selection: AnyPublisher<Selection, Never>

    private var cancellables = Set<AnyCancellable>()

    private init() {
        selection = subject
            // delay some run loop for ui to handle events
            .delay(for: .milliseconds(1), scheduler: DispatchQueue.main)
            .eraseToAnyPublisher()

        let conversations = sdb.conversationList()
        if let firstConversation = conversations.first {
            subject.send(.conversation(id: firstConversation.id))
        } else {
            let initialConversation = ConversationManager.shared.createNewConversation(autoSelect: false)
            subject.send(.conversation(id: initialConversation.id))
        }

        // Listen for conversation list changes and keep selection in sync
        ConversationManager.shared.conversations
            .receive(on: DispatchQueue.main)
            .sink { [weak self] conversationDict in
                guard let self else { return }
                if conversationDict.isEmpty {
                    if case .none = subject.value { return }
                    Logger.ui.infoFile("No conversations left, clearing selection")
                    subject.send(.none)
                    return
                }

                if case let .conversation(currentId, _) = subject.value,
                   conversationDict[currentId] != nil
                {
                    return
                }

                guard let nextConversation = conversationDict.values.first else { return }
                Logger.ui.infoFile("Selecting first available conversation id: \(nextConversation.id)")
                subject.send(.conversation(id: nextConversation.id))
            }
            .store(in: &cancellables)
    }

    func select(_ selection: Selection) {
        Logger.ui.debugFile("ChatSelection.select called with: \(selection.debugDescription)")
        subject.send(selection)
    }

    func select(_ conversationId: Conversation.ID?, options: Options = .none) {
        guard let conversationId else {
            select(.none)
            return
        }
        select(.conversation(id: conversationId, options: options))
    }

    func select(_ conversationId: Conversation.ID) {
        select(conversationId, options: .none)
    }
}

private extension ChatSelection.Selection {
    var debugDescription: String {
        switch self {
        case .none:
            "none"
        case let .conversation(id, options):
            "conversation: \(id) options: \(options.description)"
        }
    }
}

private extension ChatSelection.Options {
    var description: String {
        var components: [String] = []
        if contains(.collapseSidebar) {
            components.append("collapseSidebar")
        }
        if contains(.focusEditor) {
            components.append("focusEditor")
        }
        if components.isEmpty {
            components.append("none")
        }
        return components.joined(separator: ",")
    }
}

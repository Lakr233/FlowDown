//
//  AppDelegate+Menu.swift
//  FlowDown
//
//  Created by Alan Ye on 6/27/25.
//

import AlertController
import OrderedCollections
import Storage
import UIKit

extension AppDelegate {
    // MARK: - Menu Building

    override func buildMenu(with builder: UIMenuBuilder) {
        super.buildMenu(with: builder)
        guard builder.system == UIMenuSystem.main else { return }

        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "New Chat"),
                        action: #selector(requestNewChatFromMenu(_:)),
                        input: "n",
                        modifierFlags: .command,
                    ),
                    UIMenu(
                        title: String(localized: "New Chat with Template"),
                        options: .displayInline,
                        children: Self.buildTemplateMenuItems(target: self),
                    ),
                ],
            ),
            atStartOfMenu: .file,
        )
        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Delete Chat"),
                        action: #selector(deleteConversationFromMenu(_:)),
                        input: "\u{8}",
                        modifierFlags: [.command, .shift],
                    ),
                ],
            ),
            atEndOfMenu: .file,
        )

        if UpdateManager.shared.canCheckForUpdates {
            builder.insertSibling(
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        UIKeyCommand(
                            title: String(localized: "Check for Updates..."),
                            action: #selector(checkForUpdatesFromMenu(_:)),
                            input: "u",
                            modifierFlags: [.command, .shift],
                        ),
                    ],
                ),
                afterMenu: .preferences,
            )
        }

        builder.insertSibling(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Settings..."),
                        action: #selector(openSettingsFromMenu(_:)),
                        input: ",",
                        modifierFlags: .command,
                    ),
                ],
            ),
            afterMenu: .preferences,
        )

        #if targetEnvironment(macCatalyst)
            builder.replace(
                menu: .close,
                with: UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        UIKeyCommand(
                            title: String(localized: "Close"),
                            action: #selector(requestAppExitFromMenu(_:)),
                            input: "w",
                            modifierFlags: .command,
                        ),
                    ],
                ),
            )

            builder.replace(
                menu: .quit,
                with: UIMenu(
                    title: "",
                    options: .displayInline,
                    children: [
                        UIKeyCommand(
                            title: String(localized: "Exit"),
                            action: #selector(requestAppExitFromMenu(_:)),
                            input: "q",
                            modifierFlags: .command,
                        ),
                    ],
                ),
            )
        #endif

        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Search…"),
                        action: #selector(searchConversationsFromMenu(_:)),
                        input: "f",
                        modifierFlags: [.command, .shift],
                    ),
                ],
            ),
            atStartOfMenu: .edit,
        )
        builder.insertChild(
            UIMenu(
                title: "",
                options: .displayInline,
                children: [
                    UIKeyCommand(
                        title: String(localized: "Previous Conversation"),
                        action: #selector(selectPreviousConversationFromMenu(_:)),
                        input: UIKeyCommand.inputUpArrow,
                        modifierFlags: [.command, .alternate],
                    ),
                    UIKeyCommand(
                        title: String(localized: "Next Conversation"),
                        action: #selector(selectNextConversationFromMenu(_:)),
                        input: UIKeyCommand.inputDownArrow,
                        modifierFlags: [.command, .alternate],
                    ),
                    UIKeyCommand(
                        title: String(localized: "Toggle Sidebar"),
                        action: #selector(toggleSidebarFromMenu(_:)),
                        input: "/",
                        modifierFlags: [.control, .shift],
                    ),
                ],
            ),
            atStartOfMenu: .view,
        )
    }

    // MARK: - Template Menu

    private static func buildTemplateMenuItems(target: AppDelegate) -> [UIMenuElement] {
        let templates = Array(ChatTemplateManager.shared.templates.values)
        guard !templates.isEmpty else {
            return [UIAction(title: String(localized: "No Chat Templates"), attributes: .disabled, handler: { _ in })]
        }
        var items: [UIMenuElement] = []
        for (idx, template) in templates.enumerated() {
            let title = "\(template.name)"
            let action = #selector(AppDelegate.requestNewChatWithTemplateFromMenu(_:))
            let propertyList = template.id.uuidString
            if idx < 9 {
                let keyInput = String(idx + 1)
                items.append(
                    UIKeyCommand(
                        title: title,
                        action: action,
                        input: keyInput,
                        modifierFlags: [.command, .alternate],
                        propertyList: propertyList,
                    ),
                )
            } else {
                items.append(
                    UIAction(
                        title: title,
                        handler: { _ in
                            target.requestNewChatWithTemplateFromMenuWithID(propertyList)
                        },
                    ),
                )
            }
        }
        return items
    }

    // MARK: - Menu Actions

    var mainWindow: UIWindow? {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let windows = windowScenes.flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }

    @objc func checkForUpdatesFromMenu(_: Any?) {
        UpdateManager.shared.anchor(mainWindow?.rootViewController?.view ?? .init())
        UpdateManager.shared.performUpdateCheckFromUI()
    }

    /// Wire from MainController
    @objc func requestNewChatFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.requestNewChat()
    }

    @objc func searchConversationsFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.searchConversationsFromMenu()
    }

    @objc func openSettingsFromMenu(_: Any?) {
        (mainWindow?.rootViewController as? MainController)?.openSettings()
    }

    #if targetEnvironment(macCatalyst)
        @objc func requestAppExitFromMenu(_: Any?) {
            requestApplicationExit()
        }
    #endif

    // new chat with template

    @objc func requestNewChatWithTemplateFromMenu(_ sender: UICommand) {
        guard let templateID = sender.propertyList as? String else { return }
        requestNewChatWithTemplateFromMenuWithID(templateID)
    }

    func requestNewChatWithTemplateFromMenuWithID(_ templateID: String) {
        guard let id = UUID(uuidString: templateID),
              let template = ChatTemplateManager.shared.template(for: id)
        else { return }
        let conversationID = ChatTemplateManager.shared.createConversationFromTemplate(template)
        if let mainVC = mainWindow?.rootViewController as? MainController {
            ChatSelection.shared.select(conversationID)
            mainVC.chatView.use(conversation: conversationID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    /// conversation related
    private func withCurrentConversation(
        _ block: (MainController, Conversation.ID) -> Void,
    ) {
        guard let mainVC = mainWindow?.rootViewController as? MainController,
              let conversationID = mainVC.chatView.conversationIdentifier,
              ConversationManager.shared.conversation(identifier: conversationID) != nil
        else {
            return
        }
        block(mainVC, conversationID)
    }

    @objc func deleteConversationFromMenu(_: Any?) {
        withCurrentConversation { _, conversationID in
            let conversations = Self.sidebarOrderedIdentifiers(ConversationManager.shared.conversations.value.values)
            let nextIdentifier: Conversation.ID? = {
                guard let currentIndex = conversations.firstIndex(of: conversationID) else {
                    return nil
                }
                if currentIndex + 1 < conversations.count {
                    return conversations[currentIndex + 1]
                } else if currentIndex > 0 {
                    return conversations[currentIndex - 1]
                } else {
                    return nil
                }
            }()

            ConversationManager.shared.deleteConversation(identifier: conversationID)
            if let nextIdentifier {
                ChatSelection.shared.select(nextIdentifier)
            }
        }
    }

    /// conversation navigation
    @objc func selectPreviousConversationFromMenu(_: Any?) {
        selectAdjacentConversation(offset: -1)
    }

    @objc func selectNextConversationFromMenu(_: Any?) {
        selectAdjacentConversation(offset: 1)
    }

    private func selectAdjacentConversation(offset: Int) {
        withCurrentConversation { mainVC, conversationID in
            let list = Self.sidebarOrderedIdentifiers(ConversationManager.shared.conversations.value.values)
            guard let currentIndex = list.firstIndex(of: conversationID),
                  list.indices.contains(currentIndex + offset)
            else { return }
            let adjacentID = list[currentIndex + offset]
            ChatSelection.shared.select(adjacentID)
            mainVC.chatView.use(conversation: adjacentID) {
                mainVC.chatView.focusEditor()
            }
        }
    }

    @objc func toggleSidebarFromMenu(_: Any?) {
        if let mainVC = mainWindow?.rootViewController as? MainController {
            mainVC.view.doWithAnimation { mainVC.isSidebarCollapsed.toggle() }
        }
    }

    /// The order the sidebar shows, as built by
    /// `ConversationSelectionView.updateDataSource`: favorites first, then the
    /// rest. Both keep the creation-descending storage order, which the day
    /// sections preserve, so menu navigation steps through the visible rows.
    static func sidebarOrderedIdentifiers(
        _ conversations: some Collection<Conversation>,
    ) -> [Conversation.ID] {
        conversations.filter(\.isFavorite).map(\.id)
            + conversations.filter { !$0.isFavorite }.map(\.id)
    }
}

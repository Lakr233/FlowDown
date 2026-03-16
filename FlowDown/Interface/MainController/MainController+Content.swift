//
//  MainController+Content.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import Combine
import Foundation
import Storage
import UIKit

extension MainController {
    func setupViews() {
        textureBackground.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        sidebarLayoutView.clipsToBounds = true
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous

        contentView.layer.masksToBounds = true
        contentView.backgroundColor = .background
        contentShadowView.layer.cornerRadius = contentView.layer.cornerRadius
        contentShadowView.layer.cornerCurve = contentView.layer.cornerCurve

        contentShadowView.snp.makeConstraints { make in
            make.edges.equalTo(contentView)
        }

        sidebarDragger.snp.makeConstraints { make in
            make.right.equalTo(contentView.snp.left)
            make.top.bottom.equalToSuperview()
            make.width.equalTo(10)
        }

        contentView.hideKeyboardWhenTappedAround()

        chatView.onCreateNewChat = { [weak self] in
            self?.requestNewChat()
        }
        chatView.onSuggestNewChat = { id in
            ChatSelection.shared.select(id, options: [.collapseSidebar, .focusEditor])
        }
        chatView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        #if !targetEnvironment(macCatalyst)
            contentView.keyboardLayoutGuide.usesBottomSafeArea = false
            contentView.contentView.snp.remakeConstraints { make in
                make.left.right.top.equalToSuperview()
                make.bottom.equalTo(contentView.keyboardLayoutGuide.snp.top)
            }
        #endif

        setupChatSelectionSubscription()

        sidebar.newChatButton.delegate = self
        sidebar.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        sidebar.conversationSelectionView.tableView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }

        #if !targetEnvironment(macCatalyst)
            chatView.escapeButton.actionBlock = { [weak self] in
                self?.view.doWithAnimation {
                    self?.isSidebarCollapsed.toggle()
                }
            }
        #endif
    }

    private func setupChatSelectionSubscription() {
        ChatSelection.shared.selection
            .receive(on: DispatchQueue.main)
            .sink { [weak self] selection in
                guard let self else { return }
                switch selection {
                case .none:
                    Logger.ui.debugFile("MainController received chat selection update: none")
                    load(nil)
                case let .conversation(identifier, options):
                    let optionDescription: String = {
                        var components: [String] = []
                        if options.contains(.collapseSidebar) { components.append("collapseSidebar") }
                        if options.contains(.focusEditor) { components.append("focusEditor") }
                        return components.isEmpty ? "none" : components.joined(separator: ",")
                    }()
                    Logger.ui.debugFile("MainController received chat selection update: \(identifier) options: \(optionDescription)")
                    load(identifier)
                    if options.contains(.collapseSidebar),
                       !allowSidebarPersistence,
                       !isSidebarCollapsed
                    {
                        view.doWithAnimation { self.isSidebarCollapsed = true }
                    }
                    if options.contains(.focusEditor) {
                        Task { @MainActor in self.chatView.focusEditor() }
                    }
                }
            }
            .store(in: &cancellables)
    }

    func load(_ conv: Conversation.ID?) {
        Logger.ui.debugFile("load called with conversation: \(conv ?? "-1")")
        chatView.prepareForReuse()
        guard let identifier = conv else { return }

        chatView.use(conversation: identifier)

        let session = ConversationSessionManager.shared.session(for: identifier)
        session.updateModels()
    }
}

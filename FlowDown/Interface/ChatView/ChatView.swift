//
//  ChatView.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import Combine
import ConfigurableKit
import GlyphixTextFx
import SnapKit
import Storage
import UIKit

class ChatView: UIView {
    var conversationIdentifier: Conversation.ID?
    var cancellables: Set<AnyCancellable> = .init()
    /// Follows the tool call waiting in the conversation on screen.
    private var toolApprovalCancellable: AnyCancellable?

    let handlerColor: UIColor = .init {
        switch $0.userInterfaceStyle {
        case .light:
            .white
        default:
            .gray.withAlphaComponent(0.1)
        }
    }

    #if !targetEnvironment(macCatalyst)
        let escapeButton = FloatingIconButton(systemName: "sidebar.left").with {
            $0.accessibilityLabel = String(localized: "Toggle Sidebar")
        }

        /// The soft edge under the title row, from the top of the screen to
        /// the bottom of the header buttons, then 14 pt and a 28 pt tail.
        let topEdgeBlur = ProgressiveBlurView()
        /// The soft edge above the input: full strength at the input card's
        /// centre line, fading out 28 pt above the card.
        let bottomEdgeBlur = ProgressiveBlurView().with {
            $0.edge = .bottom
        }
        /// From the input card's centre line to the bottom of the screen, the
        /// page's own background: what scrolls there is covered, not blurred
        /// (designer, Colo, 2026-11-10).
        let bottomEdgeFill = UIView().with {
            $0.backgroundColor = .background
            $0.isUserInteractionEnabled = false
        }
    #endif

    let editor = RichEditorView()
    #if targetEnvironment(macCatalyst)
        let editorBackgroundView = UIView().with {
            $0.backgroundColor = .background
            let sep = SeparatorView()
            $0.addSubview(sep)
            sep.snp.makeConstraints { make in
                make.left.top.right.equalToSuperview()
                make.height.equalTo(1)
            }
        }
    #else
        /// No band or divider behind the input any more: the bottom edge
        /// blurs what scrolls behind it, and the input card keeps its own
        /// surface. Kept, clear, as the layout reference the insets read.
        let editorBackgroundView = UIView().with {
            $0.backgroundColor = .clear
            $0.isUserInteractionEnabled = false
        }
    #endif

    let sessionManager = ConversationSessionManager.shared
    private var messageListViews: [Conversation.ID: MessageListView] = [:]
    var currentMessageListView: MessageListView? {
        guard let id = conversationIdentifier else {
            return nil
        }
        if let listView = messageListViews[id] {
            return listView
        }

        // If the message list view is not found, create a new one.
        let listView = MessageListView()
        listView.session = sessionManager.session(for: id)
        messageListViews[id] = listView
        return listView
    }

    @TypedStorage(key: "Chat.Editor.Model.Name.Style", defaultValue: EditorModelNameStyle.trimmed)
    var editorModelNameStyle: EditorModelNameStyle {
        didSet { editor.updateModelinfoFile() }
    }

    @TypedStorage(key: "Chat.Editor.Model.Apply.Default", defaultValue: true)
    var editorApplyModelToDefault: Bool

    let title = TitleBar()

    var onCreateNewChat: (() -> Void)?
    var onSuggestNewChat: ((Conversation.ID) -> Void)?

    init() {
        super.init(frame: .zero)

        #if !targetEnvironment(macCatalyst)
            // Message lists go in below the bottom edge (`listAnchorView`).
            addSubview(bottomEdgeBlur)
            addSubview(bottomEdgeFill)
        #endif
        addSubview(editorBackgroundView)
        addSubview(editor)

        #if !targetEnvironment(macCatalyst)
            addSubview(topEdgeBlur)
            let escapeButtonGlass = escapeButton.wrappedInFloatingButtonSurface()
            addSubview(escapeButtonGlass)
        #endif

        addSubview(title)

        #if !targetEnvironment(macCatalyst)
            bringSubviewToFront(escapeButtonGlass)
        #endif

        editor.handlerColor = handlerColor
        #if !targetEnvironment(macCatalyst)
            // The card is filled with the page's own background, so its
            // top half (over the fading blur) and bottom half (over the solid
            // edge) read as one surface (designer, Colo, 2026-11-10).
            editor.cardFillColor = .background
        #endif
        editor.delegate = self
        editor.toolApproval.onDecision = { [weak self] request, decision in
            guard let self, let conversationIdentifier else { return }
            sessionManager.session(for: conversationIdentifier).toolApprovalGate.resolve(request.id, with: decision)
        }
        editor.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.bottom.equalToSuperview()
                make.centerX.equalToSuperview()
                make.width.lessThanOrEqualTo(750)
                make.width.lessThanOrEqualToSuperview()
                make.width.equalToSuperview().priority(.low)
            #else
                // Kept between the side insets too: an iPhone Duo keeps the
                // clock and the camera in a column along one side.
                make.bottom.equalTo(safeAreaLayoutGuide)
                make.centerX.equalTo(safeAreaLayoutGuide)
                make.width.lessThanOrEqualTo(750)
                make.width.lessThanOrEqualTo(safeAreaLayoutGuide)
                make.width.equalTo(safeAreaLayoutGuide).priority(.low)
            #endif
        }

        editorBackgroundView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            #if targetEnvironment(macCatalyst)
                make.bottom.equalToSuperview()
            #else
                make.bottom.equalToSuperview().offset(128)
            #endif
            make.top.equalTo(editor.snp.top).offset(-4) // for visual
        }

        sessionManager.executingSessionsPublisher
            .ensureMainThread()
            .sink { [weak self] executingSessions in
                guard let self, let conversationID = conversationIdentifier else { return }
                let isExecuting = executingSessions.contains(conversationID)
                editor.setProcessingMode(isExecuting)
            }
            .store(in: &cancellables)

        #if !targetEnvironment(macCatalyst)
            // 44 pt, centred on the same line the 40 pt button was (safe
            // area + 30), so the title row and the header keep their height.
            escapeButtonGlass.snp.makeConstraints { make in
                make.top.equalTo(safeAreaLayoutGuide).inset(8)
                make.leading.equalTo(safeAreaLayoutGuide).inset(FloatingChrome.edgeInset)
                make.width.height.equalTo(FloatingChrome.buttonSize)
            }
            title.snp.makeConstraints { make in
                make.left.top.right.equalToSuperview()
                make.bottom.equalTo(escapeButtonGlass).offset(8)
            }
        #else
            setupTitleLayout()
        #endif

        title.onCreateNewChat = { [weak self] in
            self?.onCreateNewChat?()
        }
        title.onSuggestSelection = { [weak self] id in
            self?.onSuggestNewChat?(id)
        }

        editor.heightPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                self?.setNeedsLayout()
            }
            .store(in: &cancellables)

        Self.editorModelNameStyle.onChange
            .compactMap { try? $0.decodingValue() }
            .compactMap { EditorModelNameStyle(rawValue: $0) }
            .sink { [weak self] output in self?.editorModelNameStyle = output }
            .store(in: &cancellables)

        Self.editorApplyModelToDefault.onChange
            .compactMap { try? $0.decodingValue() }
            .sink { [weak self] output in self?.editorApplyModelToDefault = output }
            .store(in: &cancellables)

        ConversationManager.removeAllEditorObjectsPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                let id = self?.conversationIdentifier
                self?.prepareForReuse()
                guard let id else { return }
                self?.use(conversation: id)
            }
            .store(in: &cancellables)

        ModelManager.shared.modelChangedPublisher
            .ensureMainThread()
            .sink { [weak self] _ in
                self?.editor.updateModelinfoFile()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("RefreshRichEditor"))
            .ensureMainThread()
            .sink { [weak self] notification in
                guard let self,
                      let conversationID = notification.object as? Conversation.ID,
                      conversationID == conversationIdentifier
                else { return }
                editor.restoreEditorStatusIfPossible()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: NSNotification.Name("TriggerSendMessage"))
            .ensureMainThread()
            .sink { [weak self] notification in
                guard let self,
                      let conversationID = notification.object as? Conversation.ID,
                      conversationID == conversationIdentifier
                else { return }
                editor.submitValues()
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func focusEditor() {
        editor.focus()
    }

    func prepareForReuse() {
        if let conversationIdentifier, sessionManager.isSessionExecuting(conversationIdentifier) {
            // A running stream keeps updating this list view, so it stays in
            // the view hierarchy and is only hidden.
            currentMessageListView?.isHidden = true
        } else {
            // Removes the current message list view from the superview.
            currentMessageListView?.removeFromSuperview()
        }
        conversationIdentifier = nil
        toolApprovalCancellable = nil
        editor.showToolApproval(nil)
        editor.prepareForReuse()
    }

    func setupTitleLayout(_ height: CGFloat? = nil) {
        title.snp.remakeConstraints { make in
            make.left.top.right.equalToSuperview()
            if let height {
                make.height.equalTo(height).priority(.high)
            }
        }
    }

    func use(conversation: Conversation.ID, completion: (() -> Void)? = nil) {
        if conversationIdentifier == conversation {
            completion?()
            return
        }
        conversationIdentifier = conversation

        // dont do it here, stream may still alive
        // ConversationSessionManager.shared.resolvePendingRefresh(for: conversation)

        if let listView = currentMessageListView {
            #if !targetEnvironment(macCatalyst)
                // The soft edges replace the system's; both together band.
                FloatingChrome.hideSystemTopEdge(of: listView.listView)
                FloatingChrome.hideSystemBottomEdge(of: listView.listView)
            #endif
            // A list view kept attached while hidden already has its constraints.
            if listView.superview !== self {
                insertSubview(listView, belowSubview: listAnchorView)
                listView.snp.makeConstraints { make in
                    #if targetEnvironment(macCatalyst)
                        make.edges.equalToSuperview()
                    #else
                        // Scrolls under the title bar and the editor, but
                        // stays out of the side insets.
                        make.top.bottom.equalToSuperview()
                        make.left.right.equalTo(safeAreaLayoutGuide)
                    #endif
                }
            }
            listView.isHidden = false
        }

        for key in messageListViews.keys {
            if key != conversation {
                messageListViews[key]?.isHidden = true
            }
        }

        editor.use(identifier: conversation)
        title.use(identifier: conversation)

        let isExecuting = sessionManager.isSessionExecuting(conversation)
        editor.setProcessingMode(isExecuting)
        updateCurrentMessageListInsets()

        toolApprovalCancellable = sessionManager.session(for: conversation).toolApprovalGate.pendingRequest
            .ensureMainThread()
            .sink { [weak self] request in
                self?.editor.showToolApproval(request)
            }

        offloadModelsToSession(modelIdentifier: modelIdentifier())
        removeUnusedListViews()
        Task { @MainActor in
            completion?()
        }
    }

    /// The view message lists are inserted below: under both soft edges on
    /// iOS, under the editor's band on the Mac.
    private var listAnchorView: UIView {
        #if targetEnvironment(macCatalyst)
            editorBackgroundView
        #else
            bottomEdgeBlur
        #endif
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateCurrentMessageListInsets()
        #if !targetEnvironment(macCatalyst)
            layoutEdgeBlurs()
        #endif
    }

    #if !targetEnvironment(macCatalyst)
        private func layoutEdgeBlurs() {
            // From the top of the screen, ignoring the safe area.
            let buttonBottom = escapeButton.convert(escapeButton.bounds, to: self).maxY
            topEdgeBlur.layoutAsBarEdge(CGRect(
                x: 0,
                y: 0,
                width: bounds.width,
                height: FloatingChrome.topEdgeHeight(buttonBottom: buttonBottom),
            ))

            // The input card (or the tool-approval card that stands in for
            // it): solid page background from its centre line down, and above
            // that a blur fading from full at the centre line to nothing
            // `tail` above the card.
            let card = editor.convert(editor.shadowContainer.frame, to: self)
            let edgeTop = max(0, card.minY - FloatingChrome.tail)
            let fillTop = max(edgeTop, card.midY)
            bottomEdgeBlur.frame = CGRect(
                x: 0,
                y: edgeTop,
                width: bounds.width,
                height: fillTop - edgeTop,
            )
            if bottomEdgeBlur.style != FloatingChrome.fullFadeEdgeStyle {
                bottomEdgeBlur.style = FloatingChrome.fullFadeEdgeStyle
            }
            bottomEdgeFill.frame = CGRect(
                x: 0,
                y: fillTop,
                width: bounds.width,
                height: max(0, bounds.height - fillTop),
            )
        }
    #endif

    private func updateCurrentMessageListInsets() {
        guard let currentMessageListView else { return }
        let visibleEditorTop = min(editor.frame.minY, editorBackgroundView.frame.minY)

        currentMessageListView.contentSafeAreaInsets = .init(
            top: title.frame.maxY + 16,
            left: 0,
            bottom: bounds.height - visibleEditorTop + 16,
            right: 0,
        )
        currentMessageListView.scrollIndicatorInsets = .init(
            top: title.frame.maxY,
            left: 0,
            bottom: bounds.height - visibleEditorTop,
            right: 0,
        )
    }

    private func removeUnusedListViews() {
        let conversationIDs: Set<Conversation.ID> = .init(ConversationManager.shared.conversations.value.keys)
        let unusedKeys = messageListViews.keys.filter { !conversationIDs.contains($0) }

        for key in unusedKeys {
            messageListViews.removeValue(forKey: key)?.removeFromSuperview()
        }
    }
}

extension ChatView {
    class TitleBar: UIView {
        let textLabel: GlyphixTextLabel = .init().with {
            #if targetEnvironment(macCatalyst)
                $0.font = .preferredFont(forTextStyle: .body).bold
            #else
                // Plain title: 17 pt semibold, primary colour.
                $0.font = .systemFont(ofSize: 17, weight: .semibold)
            #endif
            $0.isBlurEffectEnabled = false
            $0.textColor = .label
            $0.textAlignment = .center
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.clipsToBounds = false
        }

        let icon = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.tintColor = .accent
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let menuButton = EasyMenuButton().with {
            var config = UIButton.Configuration.plain()
            #if targetEnvironment(macCatalyst)
                config.image = UIImage(systemName: "chevron.down")
                $0.tintColor = .gray.withAlphaComponent(0.5)
            #else
                // A floating button: 17 pt medium symbol, primary colour.
                config.image = UIImage(systemName: "chevron.down", withConfiguration: FloatingChrome.iconConfiguration)
                config.baseForegroundColor = .label
                config.contentInsets = .zero
                $0.tintColor = .label
            #endif
            $0.imageView?.contentMode = .scaleAspectFit
            $0.configuration = config
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.showsMenuAsPrimaryAction = true
        }

        #if targetEnvironment(macCatalyst)
            let bg = UIView().with { $0.backgroundColor = .background }
            let sep = SeparatorView()
        #else
            // No background band and no divider: the chat's top soft edge
            // (`ChatView.topEdgeBlur`) sits under this bar instead.
            let backgroundContainer = ChatHeaderGlassBackgroundContainerView()
        #endif

        var cancellables: Set<AnyCancellable> = .init()

        var onCreateNewChat: (() -> Void)?
        var onSuggestSelection: ((Conversation.ID) -> Void)?

        init() {
            super.init(frame: .zero)
            translatesAutoresizingMaskIntoConstraints = false

            snp.makeConstraints { make in
                make.height.equalTo(40).priority(.low)
            }

            #if targetEnvironment(macCatalyst)
                addSubview(bg)
                bg.snp.makeConstraints { make in
                    make.left.bottom.right.equalToSuperview()
                    make.top.equalToSuperview().offset(-128)
                }
                addSubview(sep)
                sep.snp.makeConstraints { make in
                    make.left.right.equalToSuperview()
                    make.bottom.equalToSuperview()
                    make.height.equalTo(1)
                }

                addSubview(icon)
                addSubview(textLabel)
                addSubview(menuButton)

                icon.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.left.equalToSuperview().inset(20)
                    make.width.height.equalTo(24)
                }
                textLabel.snp.makeConstraints { make in
                    make.center.equalToSuperview()
                    make.top.greaterThanOrEqualToSuperview()
                    make.bottom.lessThanOrEqualToSuperview()
                    make.left.greaterThanOrEqualTo(icon.snp.right).offset(8)
                    make.right.lessThanOrEqualTo(menuButton.snp.left).offset(-8)
                }
                menuButton.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.right.equalToSuperview().inset(20)
                    make.width.height.equalTo(18)
                }
            #else
                clipsToBounds = false

                addSubview(backgroundContainer)

                backgroundContainer.contentView.addSubview(icon)
                backgroundContainer.contentView.addSubview(textLabel)

                let menuButtonGlass = menuButton.wrappedInFloatingButtonSurface()
                backgroundContainer.contentView.addSubview(menuButtonGlass)

                menuButtonGlass.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.right.equalToSuperview().inset(FloatingChrome.edgeInset)
                    make.width.height.equalTo(FloatingChrome.buttonSize)
                }

                icon.snp.makeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.left.equalToSuperview().inset(20)
                    make.width.height.equalTo(24)
                }
                textLabel.snp.makeConstraints { make in
                    make.centerX.equalToSuperview()
                    make.centerY.equalToSuperview()
                    make.top.greaterThanOrEqualToSuperview()
                    make.bottom.lessThanOrEqualToSuperview()
                    // 8 pt clear of the buttons on both sides: the sidebar
                    // button's 44 pt circle stands 16 pt in on the left.
                    make.left.greaterThanOrEqualTo(icon.snp.right).offset(8)
                    make.left.greaterThanOrEqualToSuperview()
                        .inset(FloatingChrome.edgeInset + FloatingChrome.buttonSize + 8)
                    make.right.lessThanOrEqualTo(menuButtonGlass.snp.left).offset(-8)
                }

                icon.alpha = 0
            #endif

            menuButton.menu = UIMenu(children: [
                UIDeferredMenuElement.uncached { [weak self] completion in
                    completion(self?.buildMenu()?.children ?? [])
                },
            ])

            ConversationManager.shared.conversations
                .ensureMainThread()
                .sink { [weak self] _ in
                    self?.use(identifier: self?.conv)
                }
                .store(in: &cancellables)

            #if !targetEnvironment(macCatalyst)
                _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: TitleBar, _: UITraitCollection) in
                    view.updateBackgroundInterfaceStyle()
                }
                updateBackgroundInterfaceStyle()
            #endif
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        #if !targetEnvironment(macCatalyst)
            override func layoutSubviews() {
                super.layoutSubviews()

                // The bar's background spans the whole width; its controls
                // stay inside the safe area on every side.
                let insets = safeAreaInsets
                backgroundContainer.frame = CGRect(
                    x: insets.left,
                    y: insets.top,
                    width: max(0, bounds.width - insets.left - insets.right),
                    height: max(0, bounds.height - insets.top),
                )
            }

            override func safeAreaInsetsDidChange() {
                super.safeAreaInsetsDidChange()
                setNeedsLayout()
            }
        #endif

        deinit {
            cancellables.forEach { $0.cancel() }
            cancellables.removeAll()
        }

        #if !targetEnvironment(macCatalyst)
            override func didMoveToWindow() {
                super.didMoveToWindow()
                updateBackgroundInterfaceStyle()
            }
        #endif

        private var conv: Conversation.ID?

        #if !targetEnvironment(macCatalyst)
            private func updateBackgroundInterfaceStyle() {
                backgroundContainer.update(isDark: traitCollection.userInterfaceStyle == .dark)
            }

            /// The export renders this bar on its own plain ground
            /// (`ConversationCaptureView`); the bar itself has no band left
            /// to hide, only the glass container.
            func setDecorativeBackgroundHidden(_ isHidden: Bool) {
                backgroundContainer.setVisualEffectEnabled(!isHidden)
            }
        #else
            func setDecorativeBackgroundHidden(_ isHidden: Bool) {
                bg.isHidden = isHidden
                sep.isHidden = isHidden
            }
        #endif

        func use(identifier: Conversation.ID?) {
            conv = identifier
            let conversation = ConversationManager.shared.conversation(identifier: identifier)
            icon.image = conversation?.interfaceImage
            doWithAnimation {
                self.textLabel.text = conversation?.title ?? String(localized: "Untitled")
            }
        }

        private func buildMenu() -> UIMenu? {
            guard let conv else { return nil }
            // The menu only opens from this button, so anything it presents
            // (the icon picker popover, a share sheet) points back at it
            // rather than at the middle of the full-width title bar.
            guard let convMenu = ConversationManager.shared.menu(
                forConversation: conv,
                view: menuButton,
            ) else { return nil }

            #if targetEnvironment(macCatalyst)
                // On Catalyst, only show conversation menu (new chat button is handled by sidebar)
                if let mainController = parentViewController as? MainController,
                   mainController.isSidebarCollapsed
                {
                    return UIMenu(children: [
                        convMenu,
                        UIAction(title: String(localized: "Show Sidebar"), image: UIImage(systemName: "sidebar.left")) { _ in
                            mainController.openSidebar()
                        },
                    ])
                } else {
                    return convMenu
                }
            #else
                // On iOS, show both new chat options and conversation menu
                let mainMenu = UIDeferredMenuElement.uncached { [weak self] completion in
                    guard let self else {
                        completion([])
                        return
                    }

                    let templates = ChatTemplateManager.shared.templates
                    var newChatOptions: [UIMenuElement] = []

                    newChatOptions.append(UIAction(
                        title: String(localized: "Start New Chat"),
                        image: UIImage(systemName: "plus"),
                    ) { [weak self] _ in
                        self?.onCreateNewChat?()
                    })

                    if !templates.isEmpty {
                        var templatesMenuActions: [UIAction] = []
                        for template in templates.values {
                            templatesMenuActions.append(UIAction(
                                title: template.name,
                                image: UIImage(data: template.avatar),
                            ) { [weak self] _ in
                                let convId = ChatTemplateManager.shared.createConversationFromTemplate(template)
                                self?.onSuggestSelection?(convId)
                            })
                        }
                        newChatOptions.append(UIMenu(
                            title: String(localized: "Choose Template"),
                            image: UIImage(systemName: "folder"),
                            children: templatesMenuActions,
                        ))
                    }

                    completion([
                        UIMenu(
                            title: String(localized: "New Conversation"),
                            options: [.displayInline],
                            children: newChatOptions,
                        ),
                        convMenu,
                    ])
                }
                return .init(children: [mainMenu])
            #endif
        }
    }
}

extension ChatView.TitleBar {
    class EasyMenuButton: UIButton {
        open var easyHitInsets: UIEdgeInsets = .init(top: -16, left: -16, bottom: -16, right: -16)

        override open func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
            bounds.inset(by: easyHitInsets).contains(point)
        }
    }
}

//
//  MainController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import AlertController
import Combine
import Storage
import UIKit

class MainController: UIViewController {
    let textureBackground = UIImageView().with {
        $0.image = .backgroundTexture
        $0.contentMode = .scaleAspectFill
        $0.backgroundColor = .background
        #if targetEnvironment(macCatalyst)
            $0.alpha = 0
            $0.isHidden = true
        #else
            $0.alpha = 0.2
            let vfx = UIBlurEffect(style: .regular)
            let vfxView = UIVisualEffectView(effect: vfx)
            $0.addSubview(vfxView)
            vfxView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        #endif
    }

    let sidebarLayoutView = SafeInputView()
    let sidebarDragger = SidebarDraggerView()
    let contentView = SafeInputView()
    let contentShadowView = UIView()
    let gestureLayoutGuide = UILayoutGuide()

    var hasScheduledWelcome = false

    /// Height of the window title bar area that Catalyst lets us draw under.
    /// Touches inside it move the window unless something else claims them.
    static let catalystTitleBarHeight: CGFloat = 32

    var allowSidebarPersistence: Bool {
        Self.allowsSidebarPersistence(
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            size: view.bounds.size,
        )
    }

    /// Below this width the sidebar is a drawer over the chat.
    static let drawerLayoutMaximumWidth: CGFloat = 500

    /// Whether a window this wide shows the sidebar as a drawer over the chat.
    ///
    /// This reads the window rather than the device: an iPhone that unfolds
    /// into a large display keeps the phone idiom but has the room of an iPad.
    static func usesDrawerLayout(width: CGFloat) -> Bool {
        width < drawerLayoutMaximumWidth
    }

    /// Whether the open sidebar can stay on screen next to the chat.
    ///
    /// This reads the window rather than the device, because a narrow window
    /// in Slide Over or Split View still reports a landscape device, a device
    /// laid flat reports no orientation at all, and a foldable iPhone keeps the
    /// phone idiom on its large display. It is never true below the width where
    /// `updateViewConstraints` switches to the drawer layout, since a drawer
    /// that persists can no longer be dismissed by selecting a conversation or
    /// tapping the chat.
    static func allowsSidebarPersistence(
        horizontalSizeClass: UIUserInterfaceSizeClass,
        size: CGSize,
    ) -> Bool {
        guard horizontalSizeClass == .regular,
              !usesDrawerLayout(width: size.width)
        else { return false }
        return size.width > size.height || size.width > 800
    }

    var sidebarWidth: CGFloat = 256 {
        didSet {
            guard oldValue != sidebarWidth else { return }
            scheduleSidebarLayout()
        }
    }

    /// The sidebar width after reserving the room the chat needs.
    var resolvedSidebarWidth: CGFloat {
        min(sidebarWidth, max(0, view.bounds.width - Self.minimumChatWidth))
    }

    /// The fold split the last relaxed layout used, `nil` without a fold.
    var appliedSidebarFoldSplit: SidebarFoldSplit?

    private var sidebarLayoutTick: CADisplayLink?

    /// Applies a new width once per displayed frame instead of once per change.
    ///
    /// A drag hands us a new width faster than one animated layout pass takes,
    /// and laying out on every single one starves the run loop of the commit
    /// that would present the result. Nothing reaches the screen, so no
    /// animation ever reaches its end to be reclaimed, and every following pass
    /// walks a longer list of them: a measured drag climbed from 200 live
    /// animations at 9ms to 23,000 at 38ms, with the sidebar frozen on screen
    /// the whole time. The display link only fires when the render loop
    /// actually runs, which is exactly the pace the animation can be shown at.
    func scheduleSidebarLayout() {
        guard sidebarLayoutTick == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(applySidebarLayout))
        link.add(to: .main, forMode: .common)
        sidebarLayoutTick = link
    }

    @objc private func applySidebarLayout() {
        sidebarLayoutTick?.invalidate()
        sidebarLayoutTick = nil
        view.doWithAnimation(duration: 0.2) {
            self.updateViewConstraints()
        }
    }

    static let sidebarCollapsedKey = "SidebarCollapsed"

    /// How the sidebar sits next to the chat at the current window size.
    enum SidebarPresentation {
        /// A drawer over the chat, below `drawerLayoutMaximumWidth`.
        case drawer
        /// Beside the chat, but covering it while open.
        case overlay
        /// Beside the chat, with both panes live.
        case persistent
    }

    /// The presentation the last layout pass used, `nil` before the first one.
    private var sidebarPresentation: SidebarPresentation?

    /// Set while the layout itself opens or closes the sidebar for a new
    /// window size. That is not a choice the user made, so it is not saved.
    private var isAdaptingSidebarToLayout = false

    var isSidebarCollapsed: Bool {
        didSet {
            guard oldValue != isSidebarCollapsed else { return }
            // A layout adapting to a new window size is not something the
            // user did, so it neither saves, buzzes nor flashes the dragger.
            // It lays out on its own right after.
            guard !isAdaptingSidebarToLayout else { return }
            // Opening and closing the drawer is navigation, not a preference:
            // saving it would overwrite the state the user left the sidebar in
            // on a wider layout, such as the inner display of a foldable.
            if sidebarPresentation != .drawer {
                UserDefaults.standard.set(isSidebarCollapsed, forKey: Self.sidebarCollapsedKey)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateViewConstraints()
            contentView.contentView.isUserInteractionEnabled = allowsContentInteraction
            #if !targetEnvironment(macCatalyst)
                if allowSidebarPersistence {
                    Task { [weak self] in
                        try? await Task.sleep(for: .seconds(0.25))
                        await MainActor.run {
                            self?.sidebarDragger.showDragger()
                        }
                        try? await Task.sleep(for: .seconds(0.25))
                        await MainActor.run {
                            self?.sidebarDragger.hideDragger()
                        }
                    }
                }
            #endif
        }
    }

    let chatView = ChatView().with {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    let sidebar = Sidebar().with {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }

    var bootAlertMessageQueue: [String] = []
    var cancellables: Set<AnyCancellable> = []

    static var storedSidebarCollapsed: Bool? {
        UserDefaults.standard.object(forKey: sidebarCollapsedKey) as? Bool
    }

    init() {
        // The last state the user left the sidebar in wins. Where the window
        // turns out to need the drawer, the first layout pass closes it again
        // without saving, see `adaptSidebar(to:)`.
        #if targetEnvironment(macCatalyst)
            isSidebarCollapsed = Self.storedSidebarCollapsed ?? false
        #else
            isSidebarCollapsed = Self.storedSidebarCollapsed ?? true
        #endif

        super.init(nibName: nil, bundle: nil)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(resetGestures),
            name: UIApplication.willResignActiveNotification,
            object: nil,
        )

        sidebarDragger.$currentValue
            .removeDuplicates()
            .map { CGFloat($0) }
            .ensureMainThread()
            .assign(to: \.sidebarWidth, on: self)
            .store(in: &chatView.cancellables)

        sidebarDragger.onSuggestCollapse = { [weak self] in
            guard let self else { return false }
            if isSidebarCollapsed { return false }
            view.doWithAnimation { self.isSidebarCollapsed = true }
            return true
        }

        sidebarDragger.onSuggestExpand = { [weak self] in
            guard let self else { return false }
            if !isSidebarCollapsed { return false }
            view.doWithAnimation { self.isSidebarCollapsed = false }
            return true
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        #if targetEnvironment(macCatalyst)
            view.backgroundColor = .clear
        #else
            view.backgroundColor = .background
        #endif

        view.addLayoutGuide(gestureLayoutGuide)
        view.addSubview(textureBackground)
        view.addSubview(sidebarLayoutView)
        view.addSubview(contentShadowView)
        view.addSubview(contentView)
        view.addSubview(sidebarDragger)

        sidebarLayoutView.contentView.addSubview(sidebar)
        contentView.contentView.addSubview(chatView)

        #if !targetEnvironment(macCatalyst)
            let edgePanGesture = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
            edgePanGesture.edges = .left
            edgePanGesture.delegate = self
            view.addGestureRecognizer(edgePanGesture)

            // Persistence also reads the horizontal size class, which can
            // change without the frame change `viewWillLayoutSubviews` watches.
            _ = registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (controller: MainController, _: UITraitCollection) in
                controller.view.setNeedsUpdateConstraints()
                controller.view.setNeedsLayout()
            }

            installFoldObserver()
        #endif

        setupViews()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleWelcomeIfNeeded()
    }

    /// Whether the chat side accepts input.
    ///
    /// On iPhone and on a compact iPad the open sidebar behaves like a drawer,
    /// so a tap anywhere on the chat dismisses it rather than reaching the chat.
    /// A window on the Mac has both panes on screen at once and always live.
    var allowsContentInteraction: Bool {
        #if targetEnvironment(macCatalyst)
            true
        #else
            isSidebarCollapsed || allowSidebarPersistence
        #endif
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()
        #if !targetEnvironment(macCatalyst)
            let presentation = currentSidebarPresentation
            adaptSidebar(to: presentation)
        #endif
        sidebarDragger.isCollapsed = isSidebarCollapsed
        sidebarDragger.layoutMaximalValue = Int(max(0, view.bounds.width - Self.minimumChatWidth))
        #if targetEnvironment(macCatalyst)
            setupLayoutAsCatalyst()
        #else
            switch presentation {
            case .drawer:
                setupLayoutAsCompactStyle()
            case .overlay, .persistent:
                setupLayoutAsRelaxedStyle()
            }
        #endif
    }

    /// The presentation the current window size calls for.
    var currentSidebarPresentation: SidebarPresentation {
        if Self.usesDrawerLayout(width: view.bounds.width) { return .drawer }
        if allowSidebarPersistence { return .persistent }
        return .overlay
    }

    /// Opens or closes the sidebar when the window changes how it can show it.
    ///
    /// Entering the drawer closes the sidebar, so the chat is visible and live
    /// on a phone at launch and after a foldable closes onto its outer display.
    /// Returning to a layout that keeps the sidebar beside the chat restores the
    /// state the user saved there. Neither change is saved, see `isSidebarCollapsed`.
    private func adaptSidebar(to presentation: SidebarPresentation) {
        // A view that was never laid out has no meaningful size yet.
        guard view.bounds.width > 0 else { return }
        let previous = sidebarPresentation
        sidebarPresentation = presentation
        guard previous != presentation else { return }

        var collapsed = isSidebarCollapsed
        switch presentation {
        case .drawer:
            collapsed = true
        case .persistent:
            if previous != nil, collapsed, Self.storedSidebarCollapsed == false {
                collapsed = false
            }
        case .overlay:
            break
        }
        guard collapsed != isSidebarCollapsed else { return }

        isAdaptingSidebarToLayout = true
        isSidebarCollapsed = collapsed
        isAdaptingSidebarToLayout = false
        contentView.contentView.isUserInteractionEnabled = allowsContentInteraction
    }

    private var previousFrame: CGRect = .zero

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        if previousFrame != view.frame {
            previousFrame = view.frame
            updateViewConstraints()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateShadowPath()
        contentView.contentView.isUserInteractionEnabled = allowsContentInteraction
        #if !targetEnvironment(macCatalyst)
            relayoutIfFoldMoved()
        #endif
    }

    func updateShadowPath() {
        switch contentView.layer.cornerCurve {
        case .continuous:
            contentShadowView.layer.shadowPath = UIBezierPath.continuousRoundedRect(
                view.convert(contentView.frame, to: contentShadowView),
                cornerRadius: contentView.layer.cornerRadius,
            ).cgPath
        case .circular:
            fallthrough
        default:
            contentShadowView.layer.shadowPath = UIBezierPath(
                roundedRect: view.convert(contentView.frame, to: contentShadowView),
                cornerRadius: contentView.layer.cornerRadius,
            ).cgPath
        }
    }

    var firstTouchLocation: CGPoint?
    var lastTouchBegin: Date = .init(timeIntervalSince1970: 0)
    var touchesMoved = false

    let horizontalThreshold: CGFloat = 32

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard presentedViewController == nil else { return }
        firstTouchLocation = touches.first?.location(in: view)
        touchesMoved = false

        #if targetEnvironment(macCatalyst)
            var shouldZoomWindow = false
            defer {
                if shouldZoomWindow { performZoom() }
            }
            if isTouchingHandlerBarArea(touches) {
                if Date().timeIntervalSince(lastTouchBegin) < 0.25 {
                    shouldZoomWindow = true
                }
            }
        #endif
        lastTouchBegin = .init()

        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(resetGestures),
            object: nil,
        )
        perform(#selector(resetGestures), with: nil, afterDelay: 0.25)
    }

    func isTouchingHandlerBarArea(_ touches: Set<UITouch>) -> Bool {
        #if targetEnvironment(macCatalyst)
            if presentedViewController == nil,
               touches.count == 1,
               let touch = touches.first,
               let window = view.window
            {
                // The dragger owns its whole strip, including the part that
                // overlaps the title bar. Otherwise grabbing the separator near
                // the top of the window moves the window instead of resizing.
                // A resize already under way keeps ownership even once the
                // pointer leaves the strip, which it does constantly.
                if sidebarDragger.isDragging { return false }
                if !sidebarDragger.isHidden,
                   sidebarDragger.frame.contains(touch.location(in: view))
                {
                    return false
                }
                if false
                    || touch.location(in: window).y < Self.catalystTitleBarHeight
                    || chatView.title.bounds.contains(touch.location(in: chatView))
                    || sidebar.brandingLabel.bounds.contains(
                        touch.location(in: sidebar.brandingLabel),
                    )
                {
                    return true
                }
            }
        #endif
        return false
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        #if targetEnvironment(macCatalyst)
            if isTouchingHandlerBarArea(touches) {
                dispatchTouchAsWindowMovement()
                return
            }
        #endif

        super.touchesMoved(touches, with: event)

        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(resetGestures),
            object: nil,
        )
        perform(#selector(resetGestures), with: nil, afterDelay: 0.25)
        guard presentedViewController == nil else { return }
        #if !targetEnvironment(macCatalyst)
            guard let touch = touches.first else { return }
            let currentLocation = touch.location(in: view)
            guard let firstTouchLocation else { return }
            let offsetX = currentLocation.x - firstTouchLocation.x
            guard abs(offsetX) > horizontalThreshold else { return }
            touchesMoved = true
            view.endEditing(true)
            if updateGestureStatus(withOffset: offsetX) {
                self.firstTouchLocation = touch.location(in: view)
            }
        #endif
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        // Tapping the chat only dismisses the sidebar where it acts as a
        // drawer. A window on the Mac keeps both panes, so a click there has to
        // reach the chat instead of hiding a sidebar the user asked to see.
        #if !targetEnvironment(macCatalyst)
            if presentedViewController == nil,
               let touch = touches.first,
               !isSidebarCollapsed,
               !touchesMoved,
               contentView.frame.contains(touch.location(in: view)),
               !allowSidebarPersistence
            {
                view.doWithAnimation { self.isSidebarCollapsed = true }
            }
        #endif
        resetGestures()
    }

    @objc func resetGestures() {
        firstTouchLocation = nil
        touchesMoved = false
        updateLayoutGuideToOriginalStatus()
    }

    @objc func requestNewChat() {
        let conv = ConversationManager.shared.createNewConversation()
        sidebar.newChatDidCreated(conv.id)
    }

    @objc func openSettings() {
        sidebar.settingButton.buttonAction()
    }

    func sendMessageToCurrentConversation(_ message: String) {
        Logger.app.infoFile("attempting to send message: \(message)")

        guard let currentConversationID = chatView.conversationIdentifier else {
            // showErrorAlert(title: "Error", message: "No conversation available to send message.")
            return
        }
        Logger.app.debugFile("current conversation ID: \(currentConversationID)")

        guard sdb.conversationWith(identifier: currentConversationID) != nil else {
            Logger.app.errorFile("conversation missing from database: id \(currentConversationID)")
            showErrorAlert(
                title: "Conversation Missing",
                message: "The selected conversation could not be found. Please choose another conversation or create a new one.",
            )
            return
        }

        // retrieve session
        let session = ConversationSessionManager.shared.session(for: currentConversationID)
        Logger.app.debugFile("session created/retrieved for conversation")

        let modelID = ModelManager.ModelIdentifier.defaultModelForConversation
        guard !modelID.isEmpty else {
            Logger.app.errorFile("no default model configured")
            showErrorAlert(
                title: "No Model Available",
                message: "Please add some models to use. You can choose to download models, or use cloud model from well known service providers.",
            ) {
                let setting = SettingController()
                SettingController.setNextEntryPage(.modelManagement)
                self.present(setting, animated: true)
            }
            return
        }
        Logger.app.infoFile("using model: \(modelID)")

        // check if ui was loaded
        guard let currentMessageListView = chatView.currentMessageListView else {
            return
        }

        // verify message
        let trimmedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedMessage.isEmpty else {
            showErrorAlert(
                title: "Error",
                message: "Empty message.",
            )
            return
        }
        Logger.app.debugFile("message content: '\(trimmedMessage)'")

        let editorObject = RichEditorView.Object(text: trimmedMessage)
        session.doInfere(
            modelID: modelID,
            currentMessageListView: currentMessageListView,
            inputObject: editorObject,
        ) {
            Logger.app.infoFile("message sent and AI response triggered successfully via URL scheme")
        }
    }

    private func showErrorAlert(
        title: String.LocalizationValue,
        message: String.LocalizationValue,
        completion: @escaping () -> Void = {},
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            let alert = AlertViewController(
                title: title,
                message: message,
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK") {
                    context.dispose(completion)
                }
            }
            present(alert, animated: true)
        }
    }

    @objc func openSidebar() {
        view.doWithAnimation { self.isSidebarCollapsed = false }
    }

    @objc func searchConversationsFromMenu(_: Any? = nil) {
        sidebar.searchButton.delegate?.searchButtonDidTap()
    }
}

extension MainController: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer is UIScreenEdgePanGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let edgePan = gestureRecognizer as? UIScreenEdgePanGestureRecognizer {
            return isSidebarCollapsed && edgePan.edges == .left
        }
        return true
    }
}

extension MainController: NewChatButton.Delegate {
    func newChatDidCreated(_ identifier: Conversation.ID) {
        sidebar.newChatDidCreated(identifier)
    }
}

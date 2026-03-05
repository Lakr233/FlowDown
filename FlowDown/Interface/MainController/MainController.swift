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

    var allowSidebarPersistence: Bool {
        guard UIDevice.current.userInterfaceIdiom == .pad else { return false }
        return UIDevice.current.orientation.isLandscape || view.bounds.width > 800
    }

    var sidebarWidth: CGFloat = 256 {
        didSet {
            guard oldValue != sidebarWidth else { return }
            view.doWithAnimation(duration: 0.2) {
                self.updateViewConstraints()
            }
        }
    }

    var isSidebarCollapsed: Bool {
        didSet {
            guard oldValue != isSidebarCollapsed else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            updateViewConstraints()
            contentView.contentView.isUserInteractionEnabled = isSidebarCollapsed || allowSidebarPersistence
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

    init() {
        #if targetEnvironment(macCatalyst)
            isSidebarCollapsed = false
        #else
            isSidebarCollapsed = true
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
        #endif

        setupViews()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        scheduleWelcomeIfNeeded()
    }

    private var previousLayoutRect: CGRect = .zero

    override func updateViewConstraints() {
        super.updateViewConstraints()
        #if targetEnvironment(macCatalyst)
            setupLayoutAsCatalyst()
        #else
            if UIDevice.current.userInterfaceIdiom == .phone || view.frame.width < 500 {
                setupLayoutAsCompactStyle()
            } else {
                setupLayoutAsRelaxedStyle()
            }
        #endif
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
        contentView.contentView.isUserInteractionEnabled = isSidebarCollapsed || allowSidebarPersistence
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
            withTarget: self, selector: #selector(resetGestures), object: nil,
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
                if false
                    || touch.location(in: window).y < 32
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
            withTarget: self, selector: #selector(resetGestures), object: nil,
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
        defer { resetGestures() }
        guard presentedViewController == nil else { return }
        guard let touch = touches.first else { return }
        if !isSidebarCollapsed,
           !touchesMoved,
           contentView.frame.contains(touch.location(in: view)),
           !allowSidebarPersistence
        {
            view.doWithAnimation { self.isSidebarCollapsed = true }
        }
    }

    @objc func resetGestures() {
        firstTouchLocation = nil
        touchesMoved = false
        updateLayoutGuideToOriginalStatus()
    }

    @objc private func contentViewButtonTapped() {
        #if targetEnvironment(macCatalyst)
            return
        #else
            guard !allowSidebarPersistence else { return }
            view.doWithAnimation { self.isSidebarCollapsed.toggle() }
        #endif
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
                title: "Error", message: "Empty message.",
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
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
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

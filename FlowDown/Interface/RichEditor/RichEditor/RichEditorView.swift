import UIKit

private enum RichEditorShadowStyle {
    case glass
    case legacy(UIColor)

    static func resolve(handlerColor: UIColor) -> Self {
        if #available(iOS 26, *) {
            .glass
        } else {
            .legacy(handlerColor)
        }
    }

    func applyAppearance(
        to shadowContainer: UIView,
        colorfulShadow: ColorfulShadowView
    ) {
        switch self {
        case .glass:
            shadowContainer.backgroundColor = .clear
            colorfulShadow.isHidden = true
        case let .legacy(color):
            shadowContainer.backgroundColor = color
            colorfulShadow.isHidden = false
        }
    }

    func applyGeometry(
        containerFrame: CGRect,
        cornerRadius: CGFloat,
        to colorfulShadow: ColorfulShadowView
    ) {
        switch self {
        case .glass:
            colorfulShadow.frame = .zero
        case .legacy:
            let shadowInset: CGFloat = 8
            let shadowBlur: CGFloat = 8
            colorfulShadow.frame = containerFrame.insetBy(
                dx: -shadowInset - shadowBlur,
                dy: -shadowInset - shadowBlur
            )
            colorfulShadow.updateGeometry(.init(
                innerRect: CGRect(
                    x: shadowInset + shadowBlur,
                    y: shadowInset + shadowBlur,
                    width: containerFrame.width,
                    height: containerFrame.height
                ),
                cornerRadius: cornerRadius,
                blur: shadowBlur,
                offset: .zero
            ))
        }
    }
}

class RichEditorView: EditorSectionView {
    var storage: TemporaryStorage = .init(id: "-1")

    required init() {
        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(applicationWillResignActive),
            name: UIApplication.willResignActiveNotification,
            object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    let attachmentsBar = AttachmentsBar()
    let inputEditor = InputEditor()
    let quickSettingBar = QuickSettingBar()
    let controlPanel = ControlPanel()

    let shadowContainer = UIView()
    let colorfulShadow = ColorfulShadowView()
    let dropContainer = DropView()
    let dropColorView = UIView()
    let attachmentSeprator = UIView()

    lazy var sectionSubviews: [EditorSectionView] = [
        attachmentsBar,
        inputEditor,
        quickSettingBar,
        controlPanel,
    ]

    let spacing: CGFloat = 10
    var keyboardAdditionalHeight: CGFloat = 0 {
        didSet { setNeedsLayout() }
    }

    weak var delegate: Delegate?
    var objectTransactionInProgress = false
    var heightContraints: NSLayoutConstraint = .init()

    var handlerColor: UIColor = .init {
        switch $0.userInterfaceStyle {
        case .light:
            .white
        default:
            .gray.withAlphaComponent(0.1)
        }
    } {
        didSet { applyShadowStyle() }
    }

    override func initializeViews() {
        super.initializeViews()

        addSubview(colorfulShadow)

        shadowContainer.layer.cornerRadius = 16
        shadowContainer.layer.cornerCurve = .continuous
        shadowContainer.backgroundColor = handlerColor
        shadowContainer.clipsToBounds = false
        addSubview(shadowContainer)
        applyShadowStyle()

        dropContainer.clipsToBounds = true
        dropContainer.layer.cornerRadius = shadowContainer.layer.cornerRadius
        addSubview(dropContainer)
        dropColorView.alpha = 0
        dropColorView.backgroundColor = .accent.withAlphaComponent(0.05)
        dropColorView.alpha = 0.01
        dropContainer.addSubview(dropColorView)
        dropContainer.addInteraction(UIDropInteraction(delegate: self))
        defer { bringSubviewToFront(dropContainer) }

        for subview in sectionSubviews {
            addSubview(subview)
        }

        attachmentSeprator.backgroundColor = .gray.withAlphaComponent(0.25)
        addSubview(attachmentSeprator)

        inputEditor.delegate = self
        controlPanel.delegate = self
        quickSettingBar.delegate = self
        attachmentsBar.delegate = self

        quickSettingBar.horizontalAdjustment = spacing
        Task { @MainActor in
            updateModelinfoFile()
            restoreEditorStatusIfPossible()
        }
        heightPublisher
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] output in
                self?.updateHeightConstraint(output)
            }
            .store(in: &cancellables)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var y: CGFloat = spacing
        var finalHeight: CGFloat = 0
        for subview in sectionSubviews {
            let viewHeight = subview.heightPublisher.value
            let horizontalAdjustment = subview.horizontalAdjustment

            if viewHeight > 0 {
                subview.frame = CGRect(
                    x: spacing - horizontalAdjustment,
                    y: y,
                    width: bounds.width - spacing * 2 + horizontalAdjustment * 2,
                    height: subview.heightPublisher.value,
                )
                finalHeight = subview.frame.maxY
                y = finalHeight + spacing
            } else {
                subview.frame = CGRect(
                    x: spacing - horizontalAdjustment,
                    y: y,
                    width: bounds.width - spacing * 2 + horizontalAdjustment * 2,
                    height: 0,
                )
            }
        }

        if attachmentsBar.heightPublisher.value > 0 {
            attachmentSeprator.alpha = 1
            shadowContainer.frame = .init(
                x: spacing,
                y: attachmentsBar.frame.minX,
                width: bounds.width - spacing * 2,
                height: inputEditor.frame.maxY - attachmentsBar.frame.minY,
            )
        } else {
            attachmentSeprator.alpha = 0
            shadowContainer.frame = inputEditor.frame
        }

        updateShadowGeometry()

        attachmentSeprator.frame = .init(
            x: shadowContainer.frame.minX,
            y: inputEditor.frame.minY - 0.5,
            width: shadowContainer.frame.width,
            height: 1,
        )

        dropContainer.frame = shadowContainer.frame
        dropColorView.frame = dropContainer.bounds

        heightPublisher.send(finalHeight + keyboardAdditionalHeight + spacing)
    }

    func updateHeightConstraint(_ height: CGFloat) {
        guard heightContraints.constant != height else { return }
        heightContraints.isActive = false
        heightContraints = heightAnchor.constraint(equalToConstant: height)
        heightContraints.priority = .defaultHigh
        heightContraints.isActive = true
        parentViewController?.view.layoutIfNeeded()
        setNeedsLayout()
    }

    func focus() {
        inputEditor.textView.becomeFirstResponder()
    }

    func updateModelName() {
        updateModelinfoFile()
    }

    private var shadowStyle: RichEditorShadowStyle {
        .resolve(handlerColor: handlerColor)
    }

    private func applyShadowStyle() {
        shadowStyle.applyAppearance(
            to: shadowContainer,
            colorfulShadow: colorfulShadow
        )
    }

    private func updateShadowGeometry() {
        shadowStyle.applyGeometry(
            containerFrame: shadowContainer.frame,
            cornerRadius: shadowContainer.layer.cornerRadius,
            to: colorfulShadow
        )
    }

    func prepareForReuse() {
        storage = .init(id: "-1")
        resetValues()
        updateModelName()
    }

    func use(identifier: String) {
        storage = .init(id: identifier)
        updateModelinfoFile(postUpdate: false)
        restoreEditorStatusIfPossible()
    }

    func setProcessingMode(_ isProcessing: Bool) {
        let mode: ColorfulShadowView.Mode = isProcessing ? .appleIntelligence : .idle
        colorfulShadow.mode = mode
    }

    /// used when requesting retry, inherit current option toggles
    func collectObject() -> Object {
        var text = (inputEditor.textView.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = attachmentsBar.attachmetns.values
        if text.isEmpty, !attachments.isEmpty {
            text = String(localized: "Attached \(attachments.count) Documents")
        }
        return Object(
            text: text,
            attachments: .init(attachments),
            options: [
                .storagePrefix: .url(storage.storageDir),
                .modelIdentifier: .string(quickSettingBar.modelIdentifier),
                .browsing: .bool(quickSettingBar.browsingToggle.isOn),
                .tools: .bool(quickSettingBar.toolsToggle.isOn),
                .ephemeral: .bool(false), // .ephemeral: .bool(quickSettingBar.ephemeralChatToggle.isOn),
            ],
        )
    }
}

extension RichEditorView {
    static let temporaryStorage = FileManager.default
        .temporaryDirectory
        .appendingPathComponent("RichEditor.TemporaryStorage")
}

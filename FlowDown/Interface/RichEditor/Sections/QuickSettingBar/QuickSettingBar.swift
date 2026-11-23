//
//  QuickSettingBar.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/16.
//

import UIKit

class QuickSettingBar: EditorSectionView {
    let scrollView = UIScrollView()

    let modelPicker = BlockButton(text: "", icon: "asterisk")

    let toolsToggle = ToggleBlockButton(
        text: NSLocalizedString("Tools", comment: ""),
        icon: "tools",
    )

    let terminateButton = BlockButton(
        text: NSLocalizedString("Terminate", comment: ""),
        icon: "stop.circle",
    )

    /// Drives the row's layout. The button's `isHidden` only follows it once the
    /// disappear animation has finished.
    var isTerminateVisible = false
    var terminateAction: () -> Void = {}
    var terminateTransitionID = 0
    var needsTerminateReveal = false

    /// User preference for the tools toggle, shared across conversations and launches.
    /// Models without tool call support turn the toggle off without clearing this value.
    static let toolsEnabledKey = "wiki.qaq.RichEditor.QuickSettingBar.toolsEnabled"
    static var toolsEnabledValue: Bool {
        get { UserDefaults.standard.bool(forKey: toolsEnabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: toolsEnabledKey) }
    }

    lazy var buttons: [BlockButton] = [
        modelPicker,
        toolsToggle,
        terminateButton,
    ]
    var modelIdentifier: String = ""
    var modelSupportsToolCall = false {
        didSet { toolsToggle.strikeThrough = !modelSupportsToolCall }
    }

    var computedHight: CGFloat {
        if isOpen {
            buttons.filter { !$0.isHidden }.map(\.intrinsicContentSize.height).max() ?? 0
        } else {
            0
        }
    }

    var isOpen = true {
        didSet {
            heightPublisher.send(computedHight)
            doWithAnimation { self.setNeedsLayout() }
        }
    }

    weak var delegate: Delegate?

    override func initializeViews() {
        super.initializeViews()

        scrollView.clipsToBounds = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = true
        scrollView.alwaysBounceVertical = false
        addSubview(scrollView)

        for button in buttons {
            scrollView.addSubview(button)
            if let button = button as? ToggleBlockButton {
                button.onValueChanged = { [weak self] in
                    self?.delegate?.quickSettingBarOnValueChagned()
                }
            }
        }

        configureTerminateButton()
        setModelName(nil)

        modelPicker.showsMenuAsPrimaryAction = true
        modelPicker.menu = UIMenu(children: [
            UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }
                scrollToBeforeModelItem()
                let elements = delegate?.quickSettingBarBuildModelSelectionMenu() ?? []
                completion(elements)
            },
        ])
        modelPicker.actionBlock = {}

        var requestReload: ((Bool) -> Void)!
        requestReload = { [weak self] input in
            Self.toolsEnabledValue = input
            self?.toolsToggle.isOn = input
            self?.toolsToggle.menu = .init(children: [UIDeferredMenuElement.uncached { [weak self] provider in
                let isEnabled = self?.toolsToggle.isOn ?? false
                let elements = self?.delegate?.quickSettingBarBuildAlternativeToolsMenu(
                    isEnabled: isEnabled,
                    requestReload: requestReload,
                ) ?? []
                provider(elements)
            }])
        }
        requestReload(Self.toolsEnabledValue)
        toolsToggle.showsMenuAsPrimaryAction = true
        toolsToggle.actionBlock = {}

        heightPublisher.send(computedHight)
        updateToolCallAvailability(false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        alpha = isOpen ? 1 : 0
        if isOpen { layoutButtons() }

        // Set once per pass: the centering is part of the terminate animation.
        let contentSizeWidth = scrollView.contentSize.width
        scrollView.frame = contentSizeWidth < bounds.width
            ? .init(
                x: (bounds.width - contentSizeWidth) / 2,
                y: 0,
                width: contentSizeWidth,
                height: bounds.height,
            )
            : bounds
        if isOpen { updateScrollOffsetAfterLayout() }
    }

    private func layoutButtons() {
        // The terminate button's transform belongs to its own animation.
        for button in buttons where button !== terminateButton {
            button.transform = .identity
        }
        let visibleButtons = buttons.filter {
            $0 === terminateButton ? isTerminateVisible : !$0.isHidden
        }
        let sizes = visibleButtons.map(\.intrinsicContentSize)

        var anchorX: CGFloat = horizontalAdjustment
        for (index, button) in visibleButtons.enumerated() {
            let size = sizes[index]
            assert(size.width > 0)
            assert(size.height > 0)
            place(button, x: anchorX, size: size)
            anchorX += size.width + 10
        }

        let lastOne = visibleButtons.isEmpty ? 0 : anchorX - 10
        let contentSizeWidth = lastOne + horizontalAdjustment
        scrollView.contentSize = .init(width: contentSizeWidth, height: height)
    }

    private static let defaultModelIcon = UIImage(named: "asterisk")?
        .withRenderingMode(.alwaysTemplate)

    /// Shows the model's name, with `icon` in place of the default one.
    func setModelName(_ name: String?, icon: UIImage? = nil) {
        defer { setNeedsLayout() }
        modelPicker.iconView.image = icon?.withRenderingMode(.alwaysTemplate) ?? Self.defaultModelIcon
        guard let name, !name.isEmpty else {
            modelPicker.textLabel.text = NSLocalizedString("No Model", comment: "")
            return
        }
        modelPicker.textLabel.text = name
    }

    func updateToolCallAvailability(_ availability: Bool) {
        modelSupportsToolCall = availability
        toolsToggle.isOn = availability && Self.toolsEnabledValue
    }

    func scrollToBeforeModelItem() {
        scrollView.doWithAnimation { [self] in
            scrollView.contentOffset.x = 0
        }
    }

    func scrollToAfterModelItem() {
        scrollView.doWithAnimation { [self] in
            var requiredOffset = modelPicker.frame.maxX + 10
            requiredOffset = min(requiredOffset, scrollView.contentSize.width - scrollView.frame.width)
            requiredOffset = max(0, requiredOffset)
            scrollView.contentOffset.x = requiredOffset
        }
    }

    func setModelIdentifier(_ modelIdentifier: String?) {
        self.modelIdentifier = modelIdentifier ?? ""
    }

    func hide() {
        isOpen = false
    }

    func show() {
        isOpen = true
    }
}

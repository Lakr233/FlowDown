//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import UIKit

/// A tool call as a status title at the reply's leading edge: shimmering
/// while it runs, at rest once it has finished, red when it failed. A
/// finished call opens its details.
final class ToolHintView: MessageListRowView {
    enum State {
        case running
        case suceeded
        case failed
    }

    var text: String?

    var toolName: String = .init() {
        didSet { updateContent() }
    }

    var state: State = .running {
        didSet { updateContent() }
    }

    /// Identifies the call, so a row out of the pool takes its title at once
    /// and only the same call's changes animate.
    var callID: AnyHashable? {
        didSet {
            guard callID != oldValue else { return }
            label.reset()
            label.animationIdentity = callID
            updateContent()
        }
    }

    var clickHandler: (() -> Void)?

    private let label = ThinkingStatusLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.onShownTextChange = { [weak self] in self?.setNeedsLayout() }
        label.isUserInteractionEnabled = true
        label.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(handleTap(_:))))
        contentView.addSubview(label)
        updateContent()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        clickHandler = nil
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
    }

    private func updateContent() {
        let title = switch state {
        case .running:
            String(localized: "Tool call for \(toolName) running")
        case .suceeded:
            String(localized: "Tool call for \(toolName) completed.")
        case .failed:
            String(localized: "Tool call for \(toolName) failed.")
        }
        label.text = title
        label.accessibilityLabel = title
        label.accessibilityTraits = state == .running ? .staticText : .button
        label.isThinking = state == .running
        label.textColor = state == .failed ? .systemRed : .label
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let width = min(bounds.width, label.shownTextWidth + 2)
        label.frame = contentView.directionalFrame(CGRect(
            x: 0,
            y: 0,
            width: width,
            height: Self.height(font: theme.fonts.body),
        ))
    }

    static func height(font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }

    @objc
    private func handleTap(_ sender: UITapGestureRecognizer) {
        if state != .running, sender.state == .ended {
            clickHandler?()
        }
    }
}

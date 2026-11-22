//
//  VisualInputHintBar.swift
//  FlowDown
//

import UIKit

/// A short note under the input box: the draft holds an image that the
/// selected model cannot read, the tools changed mid-conversation, or
/// Apple Intelligence Cloud is offline or near its daily limit. A note can
/// carry a row of small buttons for what the user can do next.
final class VisualInputHintBar: EditorSectionView {
    struct Action {
        let title: String
        let identifier: String
        let handler: () -> Void

        init(title: String, identifier: String = "", handler: @escaping () -> Void) {
            self.title = title
            self.identifier = identifier
            self.handler = handler
        }
    }

    let label = UILabel()
    /// The buttons, laid out by hand: leading, in reading order, wrapping
    /// to a new line when a translation is too long for one.
    private let actionRow = UIView()
    private var actionButtons: [UIButton] = []
    private var actionHandlers: [() -> Void] = []

    private let leadingInset: CGFloat = 8
    private let verticalPadding: CGFloat = 2
    private let actionSpacing: CGFloat = 4
    private let buttonSpacing: CGFloat = 16

    private(set) var isActive = false

    override func initializeViews() {
        super.initializeViews()

        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        addSubview(label)

        actionRow.isHidden = true
        addSubview(actionRow)

        alpha = 0
        isHidden = true
        heightPublisher.send(0)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.setNeedsLayout()
            self.publishHeight()
        }
    }

    /// Shows or hides the note. Returns true when it just became visible.
    @discardableResult
    func setActive(_ active: Bool, text: String, actions: [Action] = []) -> Bool {
        label.text = text
        configureActions(active ? actions : [])
        guard active != isActive else {
            if active { publishHeight() }
            return false
        }
        isActive = active
        isHidden = !active
        doWithAnimation { self.alpha = active ? 1 : 0 }
        publishHeight()
        return active
    }

    private func configureActions(_ actions: [Action]) {
        let titles = actionButtons.map { $0.configuration?.title }
        actionHandlers = actions.map(\.handler)
        guard titles != actions.map(\.title) else { return }

        for button in actionButtons {
            button.removeFromSuperview()
        }
        actionButtons = actions.enumerated().map { index, action in
            var configuration = UIButton.Configuration.plain()
            configuration.title = action.title
            configuration.contentInsets = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
            configuration.titleLineBreakMode = .byWordWrapping
            configuration.titleTextAttributesTransformer = .init { attributes in
                var attributes = attributes
                attributes.font = UIFontMetrics(forTextStyle: .footnote)
                    .scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
                return attributes
            }
            let button = UIButton(configuration: configuration)
            button.tintColor = .accent
            button.contentHorizontalAlignment = .leading
            button.tag = index
            button.accessibilityIdentifier = action.identifier.isEmpty ? nil : action.identifier
            button.addTarget(self, action: #selector(actionTapped(_:)), for: .touchUpInside)
            actionRow.addSubview(button)
            return button
        }
        actionRow.isHidden = actions.isEmpty
        setNeedsLayout()
    }

    @objc private func actionTapped(_ sender: UIButton) {
        guard actionHandlers.indices.contains(sender.tag) else { return }
        actionHandlers[sender.tag]()
    }

    private var labelWidth: CGFloat {
        max(0, bounds.width - leadingInset * 2)
    }

    /// Places the buttons within `width` and returns their frames and the
    /// total height. Nothing is moved; `layoutSubviews` applies the frames.
    private func actionLayout(width: CGFloat) -> (frames: [CGRect], height: CGFloat) {
        guard !actionButtons.isEmpty else { return ([], 0) }
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for button in actionButtons {
            let fitting = button.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            let size = CGSize(width: min(ceil(fitting.width), width), height: ceil(fitting.height))
            if x > 0, x + size.width > width {
                x = 0
                y += lineHeight + actionSpacing
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + buttonSpacing
            lineHeight = max(lineHeight, size.height)
        }
        return (frames, y + lineHeight)
    }

    private func measuredHeight() -> CGFloat {
        guard isActive else { return 0 }
        // Before the first layout the width is unknown; one line is a fair guess.
        let width = labelWidth > 0 ? labelWidth : .greatestFiniteMagnitude
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let actions = actionLayout(width: width).height
        return ceil(size.height) + verticalPadding * 2 + (actions > 0 ? actions + actionSpacing : 0)
    }

    private func publishHeight() {
        heightPublisher.send(measuredHeight())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isActive else { return }
        // Size the label from its text, not from what is left of the bounds:
        // while the height animates the bounds can be short, and the label
        // must not collapse under the buttons.
        let labelSize = label.sizeThatFits(CGSize(width: labelWidth, height: .greatestFiniteMagnitude))
        label.frame = CGRect(
            x: leadingInset,
            y: verticalPadding,
            width: labelWidth,
            height: ceil(labelSize.height),
        )
        let actions = actionLayout(width: labelWidth)
        if actions.height > 0 {
            actionRow.frame = CGRect(
                x: leadingInset,
                y: label.frame.maxY + actionSpacing,
                width: labelWidth,
                height: actions.height,
            )
            for (button, frame) in zip(actionButtons, actions.frames) {
                button.frame = frame
            }
        }
        // The width is only known now; a wrapped line changes the height.
        publishHeight()
    }
}

//
//  ToolApprovalSection.swift
//  FlowDown
//

import UIKit

/// A tool call waiting for the user, shown in place of the input: the
/// tool, why the model made the call, what it will do, then Don’t Allow
/// and Allow. Only the decision enters the conversation, on the call's row.
final class ToolApprovalSection: EditorSectionView {
    var onDecision: ((ModelToolApprovalRequest, ModelToolApprovalDecision) -> Void)?

    private(set) var request: ModelToolApprovalRequest?
    var isPresenting: Bool {
        request != nil
    }

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let sourceLabel = UILabel()
    private var detailViews: [UIView] = []
    /// The text above the buttons; a request taller than half the window
    /// scrolls from its start, under buttons that stay in place.
    private let textScroll = UIScrollView()
    private let approveButton = UIButton(type: .system)
    private let denyButton = UIButton(type: .system)

    private let inset: CGFloat = 14
    private let gap: CGFloat = 10

    override func initializeViews() {
        super.initializeViews()
        clipsToBounds = true

        iconView.contentMode = .scaleAspectFit
        iconView.tintColor = .accent
        iconView.preferredSymbolConfiguration = .init(textStyle: .headline)

        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits.insert(.header)

        sourceLabel.font = .preferredFont(forTextStyle: .subheadline)
        sourceLabel.adjustsFontForContentSizeCategory = true
        sourceLabel.textColor = .secondaryLabel
        sourceLabel.numberOfLines = 0

        var approveStyle = UIButton.Configuration.filled()
        approveStyle.baseBackgroundColor = .label
        approveStyle.baseForegroundColor = .systemBackground
        approveStyle.cornerStyle = .medium
        approveStyle.titleLineBreakMode = .byTruncatingTail
        approveStyle.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .headline)
            return attributes
        }
        approveButton.configuration = approveStyle
        approveButton.setTitle(String(localized: "Allow"), for: .normal)

        var denyStyle = UIButton.Configuration.gray()
        denyStyle.baseForegroundColor = .label
        denyStyle.cornerStyle = .medium
        denyStyle.titleLineBreakMode = .byTruncatingTail
        denyStyle.titleTextAttributesTransformer = approveStyle.titleTextAttributesTransformer
        denyButton.configuration = denyStyle
        denyButton.setTitle(String(localized: "Don’t Allow"), for: .normal)

        approveButton.addAction(UIAction { [weak self] _ in self?.decide(.approve) }, for: .touchUpInside)
        denyButton.addAction(UIAction { [weak self] _ in self?.decide(.deny) }, for: .touchUpInside)

        textScroll.contentInsetAdjustmentBehavior = .never
        textScroll.alwaysBounceVertical = false
        for view in [iconView, titleLabel, sourceLabel] {
            textScroll.addSubview(view)
        }
        for view in [textScroll, denyButton, approveButton] {
            addSubview(view)
        }

        alpha = 0
        isUserInteractionEnabled = false
        accessibilityElementsHidden = true
        heightPublisher.send(0)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.setNeedsLayout()
        }
    }

    /// Shows `request`, or hides the card when it is nil.
    func show(_ request: ModelToolApprovalRequest?) {
        guard self.request != request else { return }
        self.request = request
        if let request {
            setText(of: request)
        }
        let visible = request != nil
        alpha = visible ? 1 : 0
        isUserInteractionEnabled = visible
        accessibilityElementsHidden = !visible
        heightPublisher.send(visible ? layoutContent() : 0)
        if visible {
            UIAccessibility.post(notification: .screenChanged, argument: titleLabel)
        }
    }

    private func setText(of request: ModelToolApprovalRequest) {
        iconView.image = UIImage(systemName: request.icon) ?? UIImage(systemName: "hammer")
        titleLabel.text = request.toolName
        sourceLabel.text = request.source
        sourceLabel.isHidden = request.source == nil

        detailViews.forEach { $0.removeFromSuperview() }
        detailViews = []
        if let reason = request.reason {
            detailViews.append(makeLabel(reason, style: .body, color: .label))
        }
        if let summary = request.summary {
            detailViews.append(makeLabel(summary, style: .callout, color: .secondaryLabel))
        } else {
            let detail = ToolCallDetail(arguments: request.arguments, result: "", title: request.toolName)
            for section in detail.sections where !section.value.isEmpty {
                if let name = section.name {
                    let header = makeLabel(name, style: .footnote, color: .secondaryLabel)
                    header.accessibilityTraits.insert(.header)
                    detailViews.append(header)
                }
                detailViews.append(makeLabel(section.value, style: .callout, color: .label))
            }
        }
        detailViews.forEach { textScroll.addSubview($0) }
        textScroll.contentOffset = .zero
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle, color: UIColor) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private func decide(_ decision: ModelToolApprovalDecision) {
        guard let request else { return }
        onDecision?(request, decision)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isPresenting else { return }
        heightPublisher.send(layoutContent())
    }

    /// Places the content for the current width and returns the height it needs.
    @discardableResult
    private func layoutContent() -> CGFloat {
        let contentWidth = max(1, bounds.width - inset * 2)
        func height(of view: UIView, width: CGFloat) -> CGFloat {
            ceil(view.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height)
        }

        let iconSide = ceil(titleLabel.font.lineHeight)
        let titleX = iconSide + 8
        let titleWidth = max(1, contentWidth - titleX)
        let titleHeight = max(iconSide, height(of: titleLabel, width: titleWidth))
        iconView.frame = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
        titleLabel.frame = CGRect(x: titleX, y: 0, width: titleWidth, height: titleHeight)
        var bottom = titleLabel.frame.maxY
        if !sourceLabel.isHidden {
            let sourceHeight = height(of: sourceLabel, width: titleWidth)
            sourceLabel.frame = CGRect(x: titleX, y: bottom + 2, width: titleWidth, height: sourceHeight)
            bottom = sourceLabel.frame.maxY
        }
        for (index, detail) in detailViews.enumerated() {
            let follows = index > 0 && detailViews[index - 1].accessibilityTraits.contains(.header)
            let spacing: CGFloat = follows ? 2 : gap
            detail.frame = CGRect(
                x: 0,
                y: bottom + spacing,
                width: contentWidth,
                height: height(of: detail, width: contentWidth),
            )
            bottom = detail.frame.maxY
        }

        textScroll.contentSize = CGSize(width: contentWidth, height: bottom)
        let maximumTextHeight = (window?.bounds.height ?? .greatestFiniteMagnitude) / 2
        textScroll.frame = CGRect(x: inset, y: inset, width: contentWidth, height: min(bottom, maximumTextHeight))

        let buttonHeight = max(44, ceil(UIFont.preferredFont(forTextStyle: .headline).lineHeight + 22))
        let buttonWidth = (contentWidth - gap) / 2
        let buttonY = textScroll.frame.maxY + inset
        // Don’t Allow, then Allow, in reading order.
        let leading = CGRect(x: inset, y: buttonY, width: buttonWidth, height: buttonHeight)
        let trailing = CGRect(x: inset + buttonWidth + gap, y: buttonY, width: buttonWidth, height: buttonHeight)
        let isRightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        denyButton.frame = isRightToLeft ? trailing : leading
        approveButton.frame = isRightToLeft ? leading : trailing
        return buttonY + buttonHeight + inset
    }
}

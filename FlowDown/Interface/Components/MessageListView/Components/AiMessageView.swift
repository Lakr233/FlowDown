//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import UIKit

private enum AiMessageViewLayout {
    static let badgeSpacing: CGFloat = 8
    static let badgeCornerRadius: CGFloat = 10
}

private final class CapsuleLabel: UILabel {
    var contentInset: UIEdgeInsets = .init(top: 4, left: 10, bottom: 4, right: 10)

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return .init(width: size.width + contentInset.left + contentInset.right, height: size.height + contentInset.top + contentInset.bottom)
    }

    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let target = CGSize(
            width: max(0, size.width - contentInset.left - contentInset.right),
            height: max(0, size.height - contentInset.top - contentInset.bottom)
        )
        let base = super.sizeThatFits(target)
        return .init(width: base.width + contentInset.left + contentInset.right, height: base.height + contentInset.top + contentInset.bottom)
    }

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: contentInset))
    }
}

final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    private let modelBadgeLabel: CapsuleLabel = .init()

    var modelName: String? {
        didSet {
            guard oldValue != modelName else { return }
            updateModelBadge()
        }
    }

    var linkTapHandler: ((LinkPayload, NSRange, CGPoint) -> Void)? {
        get { markdownView.linkHandler }
        set { markdownView.linkHandler = newValue }
    }

    var codePreviewHandler: ((String?, NSAttributedString) -> Void)? {
        get { markdownView.codePreviewHandler }
        set { markdownView.codePreviewHandler = newValue }
    }

    init() {
        super.init(frame: .zero)
        configureSubviews()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        modelBadgeLabel.isHidden = true
        modelBadgeLabel.numberOfLines = 1
        modelBadgeLabel.textAlignment = .left
        modelBadgeLabel.layer.cornerRadius = AiMessageViewLayout.badgeCornerRadius
        modelBadgeLabel.layer.cornerCurve = .continuous
        modelBadgeLabel.layer.masksToBounds = true

        contentView.addSubview(modelBadgeLabel)
        contentView.addSubview(markdownView)
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        modelBadgeLabel.font = theme.fonts.footnote
        modelBadgeLabel.textColor = .secondaryLabel
        modelBadgeLabel.backgroundColor = .tertiarySystemBackground
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        modelName = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        var nextOriginY: CGFloat = 0
        if let text = modelBadgeLabel.text, !text.isEmpty, !modelBadgeLabel.isHidden {
            let size = modelBadgeLabel.sizeThatFits(CGSize(width: contentView.bounds.width, height: .greatestFiniteMagnitude))
            let width = min(size.width, contentView.bounds.width)
            modelBadgeLabel.frame = .init(origin: .zero, size: .init(width: width, height: size.height))
            nextOriginY = modelBadgeLabel.frame.maxY + AiMessageViewLayout.badgeSpacing
        } else {
            modelBadgeLabel.frame = .zero
        }

        let availableHeight = max(0, contentView.bounds.height - nextOriginY)
        markdownView.frame = .init(x: 0, y: nextOriginY, width: contentView.bounds.width, height: availableHeight)
        markdownView.bindContentOffset(from: nearestScrollView)
    }

    private func updateModelBadge() {
        if let name = modelName, !name.isEmpty {
            modelBadgeLabel.text = name
            modelBadgeLabel.isHidden = false
        } else {
            modelBadgeLabel.isHidden = true
            modelBadgeLabel.text = nil
        }
        setNeedsLayout()
    }
}

extension AiMessageView {
    static func badgeHeight(for modelName: String?, theme: MarkdownTheme, availableWidth: CGFloat) -> CGFloat {
        guard let modelName, !modelName.isEmpty, availableWidth > 0 else { return 0 }
        let label = CapsuleLabel()
        label.font = theme.fonts.footnote
        label.text = modelName
        let size = label.sizeThatFits(CGSize(width: availableWidth, height: .greatestFiniteMagnitude))
        return size.height + AiMessageViewLayout.badgeSpacing
    }
}

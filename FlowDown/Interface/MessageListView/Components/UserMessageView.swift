//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import Litext
import MarkdownView
import UIKit

/// The reader's text in a trailing, content-sized bubble with 12 pt padding
/// and corners on a 10–15% accent gradient. Mirrored right to left, where the
/// bubble sits on the left.
final class UserMessageView: MessageListRowView {
    static let contentPadding: CGFloat = 20
    static let textPadding: CGFloat = 12
    static let maximumIdealWidth: CGFloat = 800

    var text: String? {
        didSet {
            guard text != oldValue else { return }
            updateText()
        }
    }

    private let bubble = MessageAccentGradientView()
    private let textView = TextLabelView()
    /// The font and colour the text was set in, so a theme pass that changes
    /// neither leaves the text, and any selection in it, alone.
    private var textStyle: (font: UIFont, color: UIColor)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.addSubview(bubble)

        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.isAccessibilityElement = true
        contentView.addSubview(textView)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        if textStyle?.font != theme.fonts.body || textStyle?.color != theme.colors.body {
            updateText()
        }
    }

    private func updateText() {
        textStyle = (theme.fonts.body, theme.colors.body)
        textView.attributedText = .init(string: text ?? "", attributes: [
            .font: theme.fonts.body,
            .foregroundColor: theme.colors.body,
        ])
        textView.accessibilityLabel = text
        setNeedsLayout()
    }

    override var intrinsicContentSize: CGSize {
        textView.intrinsicContentSize
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let insets = MessageListView.listRowInsets(for: bounds.width)
        let textContainerWidth = Self.availableTextWidth(for: bounds.width - insets.horizontal)
        textView.preferredMaxLayoutWidth = textContainerWidth
        let textSize = textView.intrinsicContentSize
        let contentWidth = ceil(textSize.width) + Self.textPadding * 2
        contentView.frame = directionalFrame(CGRect(
            x: bounds.width - contentWidth - insets.right,
            y: 0,
            width: contentWidth,
            height: max(0, bounds.height - insets.bottom),
        ))
        bubble.frame = contentView.bounds
        textView.frame = contentView.bounds.insetBy(dx: Self.textPadding, dy: Self.textPadding)
    }

    /// The widest a bubble or the attachments over it get in a row whose
    /// content is `width` wide.
    static func availableContentWidth(for width: CGFloat) -> CGFloat {
        max(0, min(maximumIdealWidth, width - contentPadding * 2))
    }

    static func availableTextWidth(for width: CGFloat) -> CGFloat {
        max(1, availableContentWidth(for: width) - textPadding * 2)
    }
}

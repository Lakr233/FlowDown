//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import Litext
import MarkdownView
import UIKit

/// A user message: its attachments against the trailing edge, then its text
/// in a content-sized bubble with 12 pt padding and corners on a 10–15%
/// accent gradient. Mirrored right to left, where both sit on the left.
final class UserMessageView: MessageListRowView {
    static let contentPadding: CGFloat = 20
    static let textPadding: CGFloat = 12
    static let maximumIdealWidth: CGFloat = 800

    private let bubble = MessageAccentGradientView()
    private let textView = TextLabelView()
    private let attachmentsView = MessageAttachmentsView()
    private var text = ""
    /// The text and the font and colour it was set in, so a pass that changes
    /// none of them leaves the text, and any selection in it, alone.
    private var textStyle: (text: String, font: UIFont, color: UIColor)?
    private var attachments: [MessageListView.Attachments.Item] = []
    /// The message this row shows: only a change to it animates, never the
    /// row taking another message out of the pool.
    private var shownID: String?
    /// The Quick Look data source of the preview this row opened, which the
    /// preview controller only holds weakly.
    private var previewDataSource: Any?

    /// The tallest an album or a card is drawn, as the row was measured with.
    var attachmentHeightLimit: CGFloat = 0 {
        didSet {
            if attachmentHeightLimit != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// The screen's, as the row was measured with, rather than the row's
    /// own traits, which a row not yet in its window may not have.
    var displayScale: CGFloat = 0 {
        didSet {
            if displayScale != oldValue {
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        bubble.layer.cornerRadius = 12
        bubble.layer.cornerCurve = .continuous
        bubble.clipsToBounds = true
        bubble.isHidden = true
        contentView.addSubview(bubble)

        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.isAccessibilityElement = true
        textView.delegate = self
        contentView.addSubview(textView)

        attachmentsView.onPreview = { [weak self] item in
            guard let self else { return }
            previewDataSource = AttachmentsBar.presentReadOnlyPreview(for: item, from: self)
        }
        contentView.addSubview(attachmentsView)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shownID = nil
        attachments = []
        attachmentsView.show([], animated: false)
    }

    func show(_ message: MessageListView.MessageRepresentation, attachments: MessageListView.Attachments) {
        let isSameMessage = shownID == message.id
        shownID = message.id
        text = message.content
        updateText()
        self.attachments = attachments.items
        attachmentsView.show(attachments.items, animated: isSameMessage)
        bubble.isHidden = text.isEmpty
        setNeedsLayout()
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        updateText()
    }

    private func updateText() {
        guard textStyle?.text != text || textStyle?.font != theme.fonts.body || textStyle?.color != theme.colors.body
        else { return }
        textStyle = (text, theme.fonts.body, theme.colors.body)
        textView.attributedText = Self.attributedText(text, theme: theme)
        textView.accessibilityLabel = text
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let hasText = !text.isEmpty
        let available = Self.availableTextWidth(for: bounds.width)
        // The label measures itself as `height(for:)` measures it.
        let textSize = hasText ? textView.sizeThatFits(CGSize(width: available, height: 0)) : nil
        let bubbleWidth = Self.bubbleWidth(textSize: textSize, available: available)
        let attachmentWidth = available + Self.textPadding * 2
        attachmentsView.cardWidthLimit = bubbleWidth
        attachmentsView.previewHeightLimit = attachmentHeightLimit
        attachmentsView.displayScale = displayScale
        let attachmentHeight = MessageAttachmentsView.height(
            for: attachments,
            width: attachmentWidth,
            cardWidthLimit: bubbleWidth,
            maximumPreviewHeight: attachmentHeightLimit,
            displayScale: displayScale,
        )
        let gap = hasText && attachmentHeight > 0 ? MessageListView.rowSpacing : 0
        attachmentsView.frame = contentView.directionalFrame(CGRect(
            x: bounds.width - attachmentWidth,
            y: 0,
            width: attachmentWidth,
            height: attachmentHeight,
        ))
        let textHeight = textSize.map { ceil($0.height) + Self.textPadding * 2 } ?? 0
        bubble.frame = contentView.directionalFrame(CGRect(
            x: bounds.width - bubbleWidth,
            y: attachmentHeight + gap,
            width: bubbleWidth,
            height: textHeight,
        ))
        textView.frame = bubble.frame.insetBy(dx: Self.textPadding, dy: Self.textPadding)
    }

    static func height(
        for message: MessageListView.MessageRepresentation,
        attachments: MessageListView.Attachments,
        containerWidth: CGFloat,
        theme: MarkdownTheme,
        attachmentHeightLimit: CGFloat,
        displayScale: CGFloat,
    ) -> CGFloat {
        let available = availableTextWidth(for: containerWidth)
        let textSize = message.content.isEmpty ? nil : textSize(message.content, width: available, theme: theme)
        let textHeight = textSize.map { ceil($0.height) + textPadding * 2 } ?? 0
        let attachmentHeight = MessageAttachmentsView.height(
            for: attachments.items,
            width: available + textPadding * 2,
            cardWidthLimit: bubbleWidth(textSize: textSize, available: available),
            maximumPreviewHeight: attachmentHeightLimit,
            displayScale: displayScale,
        )
        let gap = textHeight > 0 && attachmentHeight > 0 ? MessageListView.rowSpacing : 0
        return textHeight + attachmentHeight + gap
    }

    /// A bubble fits its text; one with no text leaves its attachments the full width.
    private static func bubbleWidth(textSize: CGSize?, available: CGFloat) -> CGFloat {
        (textSize.map { ceil($0.width) } ?? available) + textPadding * 2
    }

    /// The widest a bubble's text gets in a row whose content is `width` wide.
    static func availableTextWidth(for width: CGFloat) -> CGFloat {
        max(1, min(maximumIdealWidth, width - contentPadding * 2) - textPadding * 2)
    }

    private static let sizingLabel = TextLabelView()

    /// Measured by Litext, which draws the text with CoreText and pins its first
    /// line to the top of the label. TextKit's `boundingRect` gives shorter
    /// lines wherever a fallback font brings a taller ascent and descent, as
    /// PingFang does for Chinese, and the text then sat low in its bubble.
    private static func textSize(_ text: String, width: CGFloat, theme: MarkdownTheme) -> CGSize {
        sizingLabel.attributedText = attributedText(text, theme: theme)
        return sizingLabel.sizeThatFits(CGSize(width: width, height: 0))
    }

    private static func attributedText(_ text: String, theme: MarkdownTheme) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: theme.fonts.body,
            .foregroundColor: theme.colors.body,
        ])
    }
}

extension UserMessageView: TextLabelViewDelegate {
    func textLabelView(
        _ label: TextLabelView,
        editMenuForSelection selection: NSRange,
        suggestedActions: [UIMenuElement],
    ) -> UIMenu? {
        ChatSelectionMenu.menu(for: label, selection: selection, suggestedActions: suggestedActions)
    }
}

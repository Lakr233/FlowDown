import UIKit

/// A user message's attachments, against the row's trailing edge: images in
/// one album, then a card for each text or audio file with its name and the
/// start of its text. Mirrored right to left.
final class MessageAttachmentsView: UIView {
    typealias Item = MessageListView.Attachments.Item

    var onPreview: ((Item) -> Void)?

    /// The widest a card is drawn.
    var cardWidthLimit: CGFloat = MessageDocumentCard.maximumWidth {
        didSet {
            if cardWidthLimit != oldValue {
                setNeedsLayout()
            }
        }
    }

    var previewHeightLimit: CGFloat = 0 {
        didSet {
            if previewHeightLimit != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// The screen's, as `height(for:…)` was given it.
    var displayScale: CGFloat = 0 {
        didSet {
            if displayScale != oldValue {
                setNeedsLayout()
            }
        }
    }

    static let spacing: CGFloat = MessageListView.rowSpacing

    private let grid = MessageImageGrid()
    private var cards: [MessageDocumentCard] = []
    private var items: [Item] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(grid)
        grid.onPreview = { [weak self] item in self?.onPreview?(item) }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    /// `animated` is the row's to say: a message gaining attachments
    /// cross-fades, a row taking another message out of the pool does not.
    func show(_ items: [Item], animated: Bool) {
        // Compared without the image bytes, which the list hands over again
        // on every update.
        guard self.items.map(Self.signature) != items.map(Self.signature) else { return }
        self.items = items
        if animated, window != nil, !UIAccessibility.isReduceMotionEnabled {
            UIView.transition(with: self, duration: 0.18, options: [.transitionCrossDissolve, .allowAnimatedContent]) {
                // Only the cross-fade: new tiles and cards start at their
                // places rather than growing out of the corner.
                UIView.performWithoutAnimation {
                    self.updateContent()
                    self.layoutIfNeeded()
                }
            }
        } else {
            UIView.performWithoutAnimation(updateContent)
        }
    }

    private func updateContent() {
        grid.show(Self.images(in: items))
        cards.forEach { $0.removeFromSuperview() }
        cards = Self.files(in: items).map { item in
            let card = MessageDocumentCard(item: item)
            card.addAction(UIAction { [weak self] _ in self?.onPreview?(item) }, for: .touchUpInside)
            addSubview(card)
            return card
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        grid.maximumSize = CGSize(width: bounds.width, height: previewHeightLimit)
        grid.displayScale = displayScale
        let size = MessageImageGrid.size(
            for: Self.images(in: items),
            width: bounds.width,
            maximumHeight: previewHeightLimit,
            displayScale: displayScale,
        )
        grid.frame = directionalFrame(
            CGRect(x: bounds.width - size.width, y: 0, width: size.width, height: size.height),
        )
        var y = size.height
        for card in cards {
            if y > 0 {
                y += Self.spacing
            }
            let width = MessageDocumentCard.width(for: card.item, maximum: min(bounds.width, cardWidthLimit))
            let height = min(previewHeightLimit, MessageDocumentCard.height(for: card.item, width: width))
            card.frame = directionalFrame(
                CGRect(x: bounds.width - width, y: y, width: width, height: height),
            )
            y += height
        }
    }

    static func height(
        for items: [Item],
        width: CGFloat,
        cardWidthLimit: CGFloat = MessageDocumentCard.maximumWidth,
        maximumPreviewHeight: CGFloat,
        displayScale: CGFloat,
    ) -> CGFloat {
        var height = MessageImageGrid.size(
            for: images(in: items),
            width: width,
            maximumHeight: maximumPreviewHeight,
            displayScale: displayScale,
        ).height
        for item in files(in: items) {
            if height > 0 {
                height += spacing
            }
            let cardWidth = MessageDocumentCard.width(for: item, maximum: min(width, cardWidthLimit))
            height += min(maximumPreviewHeight, MessageDocumentCard.height(for: item, width: cardWidth))
        }
        return height
    }

    private static func signature(_ item: Item) -> [String] {
        [item.id.uuidString, item.name, item.textRepresentation]
    }

    private static func images(in items: [Item]) -> [Item] {
        items.filter { MessageAttachmentPreviews.shared.image(for: $0) != nil }
    }

    private static func files(in items: [Item]) -> [Item] {
        items.filter { MessageAttachmentPreviews.shared.image(for: $0) == nil }
    }
}

/// A text or audio attachment: its name over up to three lines of its text,
/// on a card bordered in the bubble's accent tint.
final class MessageDocumentCard: UIControl {
    typealias Item = MessageListView.Attachments.Item

    static let maximumWidth: CGFloat = 350

    let item: Item
    private let name = UILabel()
    private let excerpt = UILabel()
    private static let padding: CGFloat = 12
    private static let excerptSpacing: CGFloat = 8
    private static let previewLines = 3
    private static let sizingExcerpt = UILabel()

    private static var nameFont: UIFont {
        UIFont.systemFont(ofSize: UIFont.preferredFont(forTextStyle: .subheadline).pointSize, weight: .semibold)
    }

    private static var excerptFont: UIFont {
        .preferredFont(forTextStyle: .subheadline)
    }

    init(item: Item) {
        self.item = item
        super.init(frame: .zero)
        backgroundColor = .secondarySystemGroupedBackground
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        clipsToBounds = true
        layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        name.font = Self.nameFont
        name.text = item.name
        name.lineBreakMode = .byTruncatingMiddle
        excerpt.font = Self.excerptFont
        excerpt.textColor = .secondaryLabel
        excerpt.numberOfLines = Self.previewLines
        excerpt.text = Self.previewText(item)
        for view in [name, excerpt] {
            view.isUserInteractionEnabled = false
            addSubview(view)
        }
        isAccessibilityElement = true
        accessibilityTraits = .button
        accessibilityLabel = item.name
        updateBorder()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(item:)")
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.6 : 1 }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let content = bounds.insetBy(dx: Self.padding, dy: Self.padding)
        let headerHeight = ceil(Self.nameFont.lineHeight)
        name.frame = directionalFrame(CGRect(x: content.minX, y: content.minY, width: content.width, height: headerHeight))
        name.textAlignment = laysOutRightToLeft ? .right : .left
        excerpt.textAlignment = name.textAlignment
        excerpt.frame = CGRect(
            x: content.minX,
            y: content.minY + headerHeight + Self.excerptSpacing,
            width: content.width,
            height: max(0, content.height - headerHeight - Self.excerptSpacing),
        )
    }

    static func height(for item: Item, width: CGFloat) -> CGFloat {
        let header = ceil(nameFont.lineHeight)
        guard let text = previewText(item), !text.isEmpty else { return padding * 2 + header }
        sizingExcerpt.font = excerptFont
        sizingExcerpt.numberOfLines = previewLines
        sizingExcerpt.text = text
        let size = sizingExcerpt.sizeThatFits(
            CGSize(width: max(1, width - padding * 2), height: .greatestFiniteMagnitude),
        )
        return padding * 2 + header + excerptSpacing + ceil(size.height)
    }

    static func width(for item: Item, maximum: CGFloat) -> CGFloat {
        let nameWidth = (item.name as NSString).size(withAttributes: [.font: nameFont]).width
        let textWidth = ((previewText(item) ?? "") as NSString).size(withAttributes: [.font: excerptFont]).width
        let naturalWidth = ceil(max(nameWidth, textWidth)) + padding * 2
        return max(1, min(maximumWidth, maximum, naturalWidth))
    }

    private static func previewText(_ item: Item) -> String? {
        let text = item.textRepresentation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        var preview = String(text.prefix(220))
        // Eight passes collapse even a run spanning the entire 220-character preview.
        for _ in 0 ..< 8 {
            guard preview.contains("\n\n") else { break }
            preview = preview.replacingOccurrences(of: "\n\n", with: "\n")
        }
        return preview
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateBorder()
    }

    private func updateBorder() {
        layer.borderColor = UIColor.accent.resolvedColor(with: traitCollection).withAlphaComponent(0.15).cgColor
    }
}

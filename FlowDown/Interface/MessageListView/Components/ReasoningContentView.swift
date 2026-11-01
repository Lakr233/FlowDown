//
//  Created by ktiays on 2025/2/21.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Litext
import UIKit

/// A reply's reasoning: a status title that shimmers "Thinking…" while the
/// model thinks and then reads how long it thought, with a chevron that
/// folds the reasoning in and out. Folded while thinking, the newest of the
/// reasoning runs along one line under the title; unfolded, the whole of it
/// sits beside a leading rule.
final class ReasoningContentView: MessageListRowView {
    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }()

    /// Between the title and the line or the text under it.
    static let bannerSpacing: CGFloat = 8
    static let textSpacing: CGFloat = 12
    /// From the leading edge to the reasoning text: the rule and its gap.
    static let textIndent: CGFloat = 16

    var thinkingDuration: TimeInterval = 0 {
        didSet { updateTitle() }
    }

    var thinkingTileTapHandler: ((_ newValue: Bool) -> Void)?

    /// Identifies the message, so a row out of the pool takes its title at
    /// once and only the same reasoning's changes animate.
    var messageID: AnyHashable? {
        didSet {
            guard messageID != oldValue else { return }
            header.reset()
            header.animationIdentity = messageID
            banner.reset()
            updateTitle()
        }
    }

    var isRevealed: Bool = false {
        didSet {
            guard isRevealed != oldValue else { return }
            animateLayout()
        }
    }

    var isThinking: Bool = false {
        didSet {
            guard isThinking != oldValue else { return }
            header.isThinking = isThinking
            updateTitle()
            animateLayout()
        }
    }

    var text: String? {
        didSet {
            guard text != oldValue else { return }
            updateText()
        }
    }

    private let header = ThinkingStatusLabel()
    private let chevron = UIImageView()
    private let banner = MessageBannerView()
    private let indicator = UIView()
    private let textView = TextLabelView()
    private var textFont: UIFont?

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.clipsToBounds = false

        header.onShownTextChange = { [weak self] in self?.setNeedsLayout() }
        header.accessibilityTraits = .button
        contentView.addSubview(header)

        chevron.image = UIImage(
            systemName: "chevron.forward",
            withConfiguration: UIImage.SymbolConfiguration(scale: .small),
        )
        chevron.contentMode = .center
        chevron.tintColor = .secondaryLabel
        chevron.isAccessibilityElement = false
        contentView.addSubview(chevron)

        contentView.addSubview(banner)

        indicator.layer.cornerRadius = 1
        indicator.backgroundColor = .secondaryLabel
        indicator.alpha = 0.6
        contentView.addSubview(indicator)

        textView.isSelectable = true
        textView.backgroundColor = .clear
        contentView.addSubview(textView)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleHeaderTap(_:)))
        tapGesture.delegate = self
        contentView.addGestureRecognizer(tapGesture)
        updateTitle()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        thinkingTileTapHandler = nil
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        header.font = theme.fonts.body
        banner.font = theme.fonts.footnote
        if textFont != theme.fonts.footnote {
            updateText()
        }
    }

    private func updateTitle() {
        header.text = isThinking
            ? String(localized: "Thinking…")
            : String(localized: "Thought for \(Int(thinkingDuration)) seconds")
        header.accessibilityLabel = header.text
    }

    private func updateText() {
        textFont = theme.fonts.footnote
        textView.attributedText = .init(string: text ?? "", attributes: [
            .font: theme.fonts.footnote,
            .foregroundColor: UIColor.secondaryLabel,
            .paragraphStyle: Self.paragraphStyle,
        ])
        setNeedsLayout()
    }

    private func animateLayout() {
        setNeedsLayout()
        guard window != nil else { return }
        doWithAnimation { self.layoutIfNeeded() }
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = contentView.bounds
        let headerHeight = Self.headerHeight(font: theme.fonts.body)
        let textWidth = min(bounds.width, header.shownTextWidth + 2)
        header.frame = contentView.directionalFrame(CGRect(x: 0, y: 0, width: textWidth, height: headerHeight))

        let chevronSize = CGSize(width: 16, height: headerHeight)
        chevron.frame = contentView.directionalFrame(CGRect(
            x: min(textWidth + 4, max(0, bounds.width - chevronSize.width)),
            y: 0,
            width: chevronSize.width,
            height: chevronSize.height,
        ))
        let quarterTurn = CGFloat.pi / 2 * (laysOutRightToLeft ? -1 : 1)
        chevron.transform = isRevealed ? CGAffineTransform(rotationAngle: quarterTurn) : .identity

        let showsBanner = Self.showsBanner(isRevealed: isRevealed, isThinking: isThinking)
        banner.alpha = showsBanner ? 1 : 0
        if showsBanner {
            banner.show(Self.bannerText(text), truncatesHead: true, animated: true)
        }
        // the line keeps the reading width, padding included; its ground is
        // drawn out to the row's edges
        let padding = MessageListView.rowHorizontalPadding
        banner.frame = CGRect(
            x: -padding,
            y: headerHeight + Self.bannerSpacing,
            width: bounds.width + padding * 2,
            height: MessageBannerView.height,
        )
        banner.textInset = padding
        let bleed = contentView.frame.minX - padding
        banner.groundBleed = UIEdgeInsets(top: 0, left: max(0, bleed), bottom: 0, right: max(0, bleed))

        let textTop = headerHeight + Self.textSpacing
        indicator.frame = contentView.directionalFrame(CGRect(
            x: 0,
            y: textTop,
            width: 2,
            height: max(0, bounds.height - textTop),
        ))
        let textFrameWidth = max(1, bounds.width - Self.textIndent)
        textView.preferredMaxLayoutWidth = textFrameWidth
        textView.frame = contentView.directionalFrame(CGRect(
            x: Self.textIndent,
            y: textTop,
            width: textFrameWidth,
            height: ceil(textView.intrinsicContentSize.height),
        ))
        indicator.alpha = isRevealed ? 0.6 : 0
        textView.alpha = isRevealed ? 1 : 0
        contentView.clipsToBounds = !showsBanner
    }

    @objc
    private func handleHeaderTap(_: UITapGestureRecognizer) {
        thinkingTileTapHandler?(!isRevealed)
    }

    /// The title and its chevron, the whole width of the row's first line.
    private var headerTapArea: CGRect {
        CGRect(x: 0, y: 0, width: contentView.bounds.width, height: Self.headerHeight(font: theme.fonts.body))
            .insetBy(dx: 0, dy: -4)
    }

    static func headerHeight(font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }

    static func showsBanner(isRevealed: Bool, isThinking: Bool) -> Bool {
        !isRevealed && isThinking
    }

    /// The newest of the reasoning, on one line.
    private static func bannerText(_ text: String?) -> String {
        String((text ?? "").suffix(200))
    }
}

extension ReasoningContentView: UIGestureRecognizerDelegate {
    /// Only a tap on the title line folds the reasoning; one on the
    /// reasoning text belongs to its selection.
    func gestureRecognizer(_: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        headerTapArea.contains(touch.location(in: contentView))
    }
}

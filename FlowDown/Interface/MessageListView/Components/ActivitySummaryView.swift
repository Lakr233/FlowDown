//
//  ActivitySummaryView.swift
//  FlowDown
//

import UIKit

/// A summary in the transcript, which opens its trace (`TraceController`).
/// While the turn is at work on it the title shimmers, and the newest call
/// is the line under it.
final class ActivitySummaryView: MessageListRowView {
    var onOpenTrace: (() -> Void)?

    private let header = ThinkingStatusLabel()
    private let bannerView = MessageBannerView()
    /// The summary this row shows: only a change to it animates, never the
    /// row taking another summary out of the pool.
    private var shownID: String?
    /// Between the title and the line under it.
    static let bannerSpacing: CGFloat = 8

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.addSubview(header)
        bannerView.isHidden = true
        bannerView.textInset = MessageListView.rowHorizontalPadding
        contentView.addSubview(bannerView)
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(openTrace)))
        header.onShownTextChange = { [weak self] in
            self?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ summary: MessageListView.ActivitySummary) {
        let isSameSummary = shownID == summary.id
        shownID = summary.id
        let title = summary.title
        header.animationIdentity = summary.id
        header.text = title
        header.isAccessibilityElement = true
        header.accessibilityLabel = title
        header.accessibilityTraits = .button
        header.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: String(localized: "View Thoughts")) { [weak self] _ in
                self?.onOpenTrace?()
                return true
            },
        ]
        if let banner = summary.banner {
            bannerView.show(banner, animated: isSameSummary)
            bannerView.isHidden = false
        } else {
            bannerView.reset()
            bannerView.isHidden = true
        }
        header.isThinking = summary.isRunning
        setNeedsLayout()
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        header.font = theme.fonts.body
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shownID = nil
        header.isThinking = false
        header.reset()
        header.accessibilityCustomActions = nil
        bannerView.reset()
        bannerView.isHidden = true
        onOpenTrace = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let scale = max(traitCollection.displayScale, 1)
        func pixel(_ value: CGFloat) -> CGFloat {
            (value * scale).rounded() / scale
        }
        let height = Self.headerHeight(font: theme.fonts.body)
        header.frame = CGRect(x: 0, y: 0, width: pixel(bounds.width), height: pixel(height))
        if !bannerView.isHidden {
            // the line keeps the reading width, padding included; its
            // ground is drawn out to the row's edges
            let padding = MessageListView.rowHorizontalPadding
            let frame = CGRect(
                x: -padding,
                y: header.frame.maxY + Self.bannerSpacing,
                width: bounds.width + padding * 2,
                height: MessageBannerView.height,
            )
            bannerView.frame = frame
            let rowFrame = convert(frame, from: contentView)
            bannerView.groundBleed = UIEdgeInsets(
                top: 0,
                left: max(0, rowFrame.minX),
                bottom: 0,
                right: max(0, self.bounds.width - rowFrame.maxX),
            )
        }
    }

    static func headerHeight(font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }

    static func height(for summary: MessageListView.ActivitySummary, font: UIFont) -> CGFloat {
        var height = headerHeight(font: font)
        if summary.banner != nil {
            height += bannerSpacing + MessageBannerView.height
        }
        return height
    }

    @objc private func openTrace() {
        onOpenTrace?()
    }
}

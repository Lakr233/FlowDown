//
//  ActivitySummaryView.swift
//  FlowDown
//

import UIKit

/// A summary in the transcript, which opens its trace (`TraceController`).
/// While the turn is at work on it the title shimmers, and the newest call
/// is the line under it. A summary that lists its steps
/// (`InlineActivityStepsSetting`) has every step under the title instead,
/// in order: each thought's whole text and each call's line, set by
/// `ActivityStepText`.
final class ActivitySummaryView: MessageListRowView {
    var onOpenTrace: (() -> Void)?

    private let header = ThinkingStatusLabel()
    private let bannerView = MessageBannerView()
    /// The steps listed under the title, each in the pieces it is set in.
    private var listedSteps: [(wraps: Bool, pieces: [String])] = []
    /// A label for each piece listed, in order; spares stay hidden.
    private var stepLabels: [UILabel] = []
    /// Where, how wide and in what font the listed steps were last laid
    /// out; nil once they change, so a layout pass for anything else leaves
    /// them be.
    private var stepLayout: (top: CGFloat, width: CGFloat, font: UIFont)?
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
        let traceAction = summary.hasThoughts ? String(localized: "View Thoughts") : String(localized: "Trace")
        header.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: traceAction) { [weak self] _ in
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
        showSteps(summary.inlineSteps)
        setNeedsLayout()
    }

    private func showSteps(_ steps: [MessageListView.ActivitySummary.InlineStep]) {
        listedSteps = steps.map { step in
            (wraps: step.kind == .thought, pieces: ActivityStepText.pieces(of: step))
        }
        stepLayout = nil
        let font = theme.fonts.footnote
        var index = 0
        for step in listedSteps {
            for piece in step.pieces {
                if index == stepLabels.count {
                    let label = UILabel()
                    contentView.addSubview(label)
                    stepLabels.append(label)
                }
                let label = stepLabels[index]
                ActivityStepText.configure(label, wraps: step.wraps, font: font)
                if label.text != piece {
                    label.text = piece
                }
                label.isHidden = false
                index += 1
            }
        }
        for label in stepLabels[index...] where !label.isHidden {
            label.isHidden = true
            label.text = nil
        }
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        header.font = theme.fonts.body
        let font = theme.fonts.footnote
        for label in stepLabels where label.font != font {
            label.font = font
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shownID = nil
        header.isThinking = false
        header.reset()
        header.accessibilityCustomActions = nil
        bannerView.reset()
        bannerView.isHidden = true
        showSteps([])
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
        layoutSteps(width: bounds.width, below: header.frame.maxY)
    }

    /// Each step a spacing below the one before, at the body text's edge.
    private func layoutSteps(width: CGFloat, below top: CGFloat) {
        let font = theme.fonts.footnote
        if let stepLayout, stepLayout.top == top, stepLayout.width == width, stepLayout.font == font {
            return
        }
        stepLayout = (top, width, font)
        var y = top
        var index = 0
        for step in listedSteps {
            y += Self.bannerSpacing
            for piece in step.pieces {
                let height = ActivityStepText.height(of: piece, wraps: step.wraps, font: font, width: width)
                stepLabels[index].frame = CGRect(x: 0, y: y, width: width, height: height)
                y += height
                index += 1
            }
        }
    }

    static func headerHeight(font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }

    /// `font`: the title's. `stepFont`, `width`: the listed steps' font and
    /// the width they wrap in, the row's content width.
    static func height(
        for summary: MessageListView.ActivitySummary,
        font: UIFont,
        stepFont: UIFont,
        width: CGFloat,
    ) -> CGFloat {
        var height = headerHeight(font: font)
        if summary.banner != nil {
            height += bannerSpacing + MessageBannerView.height
        }
        for step in summary.inlineSteps {
            height += bannerSpacing + ActivityStepText.height(of: step, font: stepFont, width: width)
        }
        return height
    }

    @objc private func openTrace() {
        onOpenTrace?()
    }
}

//
//  ActivitySummaryView.swift
//  FlowDown
//

import LitextAnimation
import UIKit

/// A summary in the transcript, which opens its trace (`TraceController`).
/// While the turn is at work on it the title shimmers, and the newest call
/// is the line under it. A summary that lists its steps
/// (`InlineActivityStepsSetting`) has every step under the title instead,
/// in order: each thought's whole text and each call's line, set by
/// `ActivityStepText`.
///
/// The steps of the summary a row already shows change as the reply does: a
/// thought's streamed text fades in (`ChatMarkdownView.reveal`), a step comes
/// and goes in the time the line under the title changes its text
/// (`MessageBannerView.textFadeDuration`), and the steps after it move on
/// the list's spring, as the rows after this one do. Under Reduce Motion,
/// off screen, and for a row taking another summary, nothing animates.
final class ActivitySummaryView: MessageListRowView {
    var onOpenTrace: (() -> Void)?

    private let header = ThinkingStatusLabel()
    private let bannerView = MessageBannerView()
    /// The pieces the steps listed under the title are set in, in order.
    private var pieces: [ActivityStepText.Piece] = []
    /// The label showing each piece: a thought's or a call's.
    private var pieceLabels: [String: UIView] = [:]
    /// Labels no piece is shown in, kept hidden.
    private var spareThoughtLabels: [LTXAnimatableLabel] = []
    private var spareCallLabels: [UILabel] = []
    /// The font the listed pieces are set in.
    private var stepFont: UIFont?
    /// Pieces whose labels have yet to be put in place.
    private var unplacedPieces: Set<String> = []
    /// The next layout moves the steps already in place on the list's spring.
    private var animatesStepLayout = false
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
        let animatesSteps = Self.animatesSteps(
            isSameSummary: isSameSummary,
            isInWindow: window != nil,
            reduceMotion: UIAccessibility.isReduceMotionEnabled,
        )
        showSteps(summary.inlineSteps, animated: animatesSteps)
        setNeedsLayout()
    }

    /// Whether a change to the listed steps animates: only on screen, in
    /// the summary the row already shows, and never under Reduce Motion.
    static func animatesSteps(isSameSummary: Bool, isInWindow: Bool, reduceMotion: Bool) -> Bool {
        isSameSummary && isInWindow && !reduceMotion
    }

    private func showSteps(_ steps: [MessageListView.ActivitySummary.InlineStep], animated: Bool) {
        let listed = ActivityStepText.pieces(of: steps)
        let change = ActivityStepText.Change(from: pieces, to: listed)
        let font = theme.fonts.footnote
        pieces = listed
        stepFont = font
        stepLayout = nil
        animatesStepLayout = animated
        var labels: [String: UIView] = [:]
        for piece in listed {
            if let label = pieceLabels.removeValue(forKey: piece.key) {
                // a thought's text that grew fades in
                fill(label, with: piece, font: font, animated: animated)
                labels[piece.key] = label
                continue
            }
            let label = takeLabel(for: piece)
            // a thought that grew into another piece keeps streaming there;
            // any other piece is a new step, which comes in whole
            let streams = animated && change.continued.contains(piece.key)
            fill(label, with: piece, font: font, animated: streams)
            label.isHidden = false
            fade(label, animated: animated && !streams)
            unplacedPieces.insert(piece.key)
            labels[piece.key] = label
        }
        for (key, label) in pieceLabels {
            unplacedPieces.remove(key)
            retire(label, animated: animated)
        }
        pieceLabels = labels
    }

    /// A hidden, empty label for `piece`, from the spares or new.
    private func takeLabel(for piece: ActivityStepText.Piece) -> UIView {
        guard piece.wraps else {
            if let label = spareCallLabels.popLast() { return label }
            let label = UILabel()
            label.isHidden = true
            contentView.addSubview(label)
            return label
        }
        let label = spareThoughtLabels.popLast() ?? {
            let label = ActivityStepText.makeThoughtLabel()
            label.isHidden = true
            contentView.addSubview(label)
            return label
        }()
        // the label starts on this piece with no text, so text set after it
        // is more of the same piece and may fade in
        label.animationIdentity = piece.key
        label.setAttributedText(NSAttributedString(), animated: false)
        return label
    }

    private func fill(_ label: UIView, with piece: ActivityStepText.Piece, font: UIFont, animated: Bool) {
        if let label = label as? LTXAnimatableLabel {
            label.setAttributedText(ActivityStepText.thoughtText(piece.text, font: font), animated: animated)
            label.accessibilityLabel = piece.text
        } else if let label = label as? UILabel {
            ActivityStepText.configure(label, wraps: false, font: font)
            if label.text != piece.text {
                label.text = piece.text
            }
        }
    }

    /// Hides a label and empties it for the next piece to take.
    private func retire(_ label: UIView, animated: Bool) {
        label.isHidden = true
        fade(label, animated: animated)
        if let label = label as? LTXAnimatableLabel {
            label.setAttributedText(NSAttributedString(), animated: false)
            label.accessibilityLabel = nil
            spareThoughtLabels.append(label)
        } else if let label = label as? UILabel {
            label.text = nil
            spareCallLabels.append(label)
        }
    }

    /// Fades a label that was just shown or hidden, as the line under the
    /// title fades its next text in; not animated, it changes at once.
    private func fade(_ label: UIView, animated: Bool) {
        // a layer keeps its transition under this key, whichever it is added with
        guard animated else {
            label.layer.removeAnimation(forKey: kCATransition)
            return
        }
        let fade = CATransition()
        fade.type = .fade
        fade.duration = MessageBannerView.textFadeDuration
        label.layer.add(fade, forKey: kCATransition)
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        header.font = theme.fonts.body
        let font = theme.fonts.footnote
        guard let stepFont, stepFont != font else { return }
        self.stepFont = font
        for piece in pieces {
            guard let label = pieceLabels[piece.key] else { continue }
            fill(label, with: piece, font: font, animated: false)
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
        showSteps([], animated: false)
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
    /// A label takes its size at once. One already in place moves to its
    /// new place on the list's spring when the steps changed animated;
    /// anything else is put there.
    private func layoutSteps(width: CGFloat, below top: CGFloat) {
        let font = theme.fonts.footnote
        if let stepLayout, stepLayout.top == top, stepLayout.width == width, stepLayout.font == font {
            return
        }
        stepLayout = (top, width, font)
        let animated = animatesStepLayout
        animatesStepLayout = false
        var moves: [(label: UIView, frame: CGRect)] = []
        var y = top
        var stepID: String?
        for piece in pieces {
            if piece.stepID != stepID {
                stepID = piece.stepID
                y += Self.bannerSpacing
            }
            let height = ActivityStepText.height(of: piece.text, wraps: piece.wraps, font: font, width: width)
            let frame = CGRect(x: 0, y: y, width: width, height: height)
            y += height
            guard let label = pieceLabels[piece.key] else { continue }
            let slides = animated && !unplacedPieces.contains(piece.key) && label.frame.origin != frame.origin
            UIView.performWithoutAnimation {
                label.frame = slides ? CGRect(origin: label.frame.origin, size: frame.size) : frame
            }
            if slides {
                moves.append((label, frame))
            }
        }
        unplacedPieces.removeAll()
        guard !moves.isEmpty else { return }
        withAnimation {
            for move in moves {
                move.label.frame = move.frame
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

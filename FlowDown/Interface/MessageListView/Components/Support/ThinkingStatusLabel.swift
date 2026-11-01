import LitextAnimation
import UIKit

/// A status title in the transcript. On screen it changes at most once a
/// second: the first change shows at once, and whatever arrives within the
/// second waits, the latest of it shown when the second is up, so a status
/// flipping quickly never cuts a transition short. While `isThinking` a
/// shimmer sweeps the text; at rest it is drawn at half opacity.
final class ThinkingStatusLabel: LTXAnimatableLabel {
    private static let minimumInterval: TimeInterval = 1

    var font = UIFont.preferredFont(forTextStyle: .body) {
        didSet {
            if font != oldValue {
                updateText(animated: false)
            }
        }
    }

    /// The colour of the text, drawn at half its opacity at rest.
    var textColor: UIColor = .label {
        didSet {
            if textColor != oldValue {
                updateText(animated: false)
            }
        }
    }

    var text: String? {
        didSet { requestText() }
    }

    /// Called whenever what is drawn changes: what sits after the text moves
    /// with it.
    var onShownTextChange: (() -> Void)?

    /// How wide the drawn text is.
    var shownTextWidth: CGFloat {
        ceil(NSAttributedString(string: shown ?? "", attributes: [.font: font]).size().width)
    }

    var isThinking = false {
        didSet {
            if isThinking != oldValue {
                updateShimmer()
            }
        }
    }

    /// What is drawn, which trails `text` while a change waits its turn.
    private var shown: String?
    private var shownIdentity: AnyHashable?
    private var lastChange: Date = .distantPast
    private var pending: DispatchWorkItem?
    private let shimmer = ShimmerLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        animator = LTXNumericTransitionAnimator()
        animationPolicy = LTXNumericTransitionAnimator.policy
        isSelectable = false
        isAccessibilityElement = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateShimmer),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification,
            object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    /// Takes the text at once, for a row taking another message out of the
    /// pool.
    func reset() {
        pending?.cancel()
        pending = nil
        animationIdentity = nil
        shownIdentity = nil
        lastChange = .distantPast
        text = nil
    }

    /// Another row's text, or a label off screen, takes the text at once.
    private func requestText() {
        guard text != shown || pending != nil else { return }
        pending?.cancel()
        pending = nil
        guard window != nil, shownIdentity == animationIdentity else {
            show(animated: false)
            return
        }
        let wait = lastChange.addingTimeInterval(Self.minimumInterval).timeIntervalSinceNow
        guard wait > 0 else {
            show(animated: true)
            return
        }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pending = nil
            show(animated: window != nil)
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: item)
    }

    private func show(animated: Bool) {
        shownIdentity = animationIdentity
        guard text != shown else { return }
        shown = text
        if animated {
            lastChange = Date()
        }
        updateText(animated: animated)
    }

    /// While thinking the text is opaque and the shimmer's resting half alpha
    /// dims it to the same 50% the resting text is drawn in. Right to left it
    /// is set against the right edge, where the shimmer is.
    private func updateText(animated: Bool) {
        let color = layer.mask == nil ? textColor.withAlphaComponent(0.5) : textColor
        var attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        if laysOutRightToLeft {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .right
            attributes[.paragraphStyle] = paragraph
        }
        let animates = animated && !UIAccessibility.isReduceMotionEnabled
        setAttributedText(NSAttributedString(string: shown ?? "", attributes: attributes), animated: animates)
        setNeedsLayout()
        onShownTextChange?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        shimmer.fit(width: shownTextWidth, in: bounds, rightToLeft: laysOutRightToLeft)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateShimmer()
    }

    @objc private func updateShimmer() {
        shimmer.stop()
        let shimmers = isThinking && window != nil && !UIAccessibility.isReduceMotionEnabled
        if shimmers != (layer.mask != nil) {
            layer.mask = shimmers ? shimmer : nil
            updateText(animated: false)
        }
        if shimmers {
            shimmer.start()
        }
    }
}

//
//  ToolsChangeHintView.swift
//  FlowDown
//

import UIKit

/// A note floating above the input box after the tools change
/// mid-conversation. It takes no layout space: the editor places it 8 pt
/// above the card, centred, so neither the card nor the buttons below move
/// when it comes and goes. It never takes touches; what is under it, the
/// message list, keeps them.
final class ToolsChangeHintView: UIView {
    let label = UILabel()

    /// The capsule that slides and fades. The view itself is a plain host whose
    /// alpha the editor uses to hide the note while a tool call covers the input.
    private let capsule = UIView()
    private let fillView = UIView()
    private var glassView: UIVisualEffectView?

    private let horizontalPadding: CGFloat = 12
    private let verticalPadding: CGFloat = 6
    /// The gap between the capsule's bottom and the input box's top edge.
    static let gapAboveInput: CGFloat = 8

    private(set) var isActive = false

    /// The surface behind the text: the input card's own fill.
    var fillColor: UIColor = .background {
        didSet { fillView.backgroundColor = fillColor }
    }

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        clipsToBounds = false

        capsule.isUserInteractionEnabled = false
        capsule.clipsToBounds = false
        addSubview(capsule)

        fillView.backgroundColor = fillColor
        fillView.layer.cornerCurve = .continuous
        fillView.clipsToBounds = true
        capsule.addSubview(fillView)

        // The input card's border: glass over the opaque fill from iOS 26,
        // a hairline edge before.
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                let effectView = UIVisualEffectView(effect: UIGlassEffect())
                effectView.isUserInteractionEnabled = false
                effectView.layer.cornerCurve = .continuous
                effectView.clipsToBounds = true
                capsule.addSubview(effectView)
                glassView = effectView
            }
        #endif
        if glassView == nil {
            fillView.layer.borderWidth = 1 / max(1, traitCollection.displayScale)
            fillView.layer.borderColor = UIColor.label.withAlphaComponent(0.1).cgColor
        }

        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.textAlignment = .center
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        capsule.addSubview(label)

        capsule.alpha = 0
        capsule.isHidden = true

        registerForTraitChanges([
            UITraitPreferredContentSizeCategory.self,
            UITraitUserInterfaceStyle.self,
        ]) { (self: Self, _) in
            if self.glassView == nil {
                self.fillView.layer.borderColor = UIColor.label.withAlphaComponent(0.1).cgColor
            }
            self.superview?.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    /// The capsule's size for its text, no wider than `maxWidth`.
    func preferredSize(maxWidth: CGFloat) -> CGSize {
        let textSize = label.sizeThatFits(CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude,
        ))
        let height = ceil(label.font.lineHeight) + verticalPadding * 2
        let width = min(max(0, maxWidth), ceil(textSize.width) + horizontalPadding * 2)
        return CGSize(width: width, height: height)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Bounds and centre, not frame: the capsule may be mid-slide.
        capsule.bounds = bounds
        capsule.center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.height / 2
        fillView.frame = capsule.bounds
        fillView.layer.cornerRadius = radius
        glassView?.frame = capsule.bounds
        glassView?.layer.cornerRadius = radius
        label.frame = capsule.bounds.insetBy(dx: horizontalPadding, dy: verticalPadding)
    }

    /// Shows or hides the note. Returns true when it just became visible.
    @discardableResult
    func setActive(_ active: Bool, text: String) -> Bool {
        if active || !text.isEmpty { label.text = text }
        guard active != isActive else {
            if active { superview?.setNeedsLayout() }
            return false
        }
        isActive = active
        superview?.setNeedsLayout()
        if active {
            appear()
        } else {
            disappear()
        }
        return active
    }

    private var animates: Bool {
        window != nil
    }

    private func appear() {
        superview?.layoutIfNeeded()
        capsule.isHidden = false
        guard animates else {
            capsule.transform = .identity
            capsule.alpha = 1
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        capsule.transform = reduceMotion ? .identity : CGAffineTransform(translationX: 0, y: 8)
        UIView.animate(
            withDuration: 0.3,
            delay: 0,
            options: [.curveEaseOut, .beginFromCurrentState, .allowUserInteraction],
        ) {
            self.capsule.transform = .identity
            self.capsule.alpha = 1
        }
    }

    private func disappear() {
        guard animates else {
            capsule.transform = .identity
            capsule.alpha = 0
            capsule.isHidden = true
            return
        }
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.curveEaseIn, .beginFromCurrentState, .allowUserInteraction],
        ) {
            self.capsule.alpha = 0
            if !reduceMotion {
                self.capsule.transform = CGAffineTransform(translationX: 0, y: 4)
            }
        } completion: { _ in
            guard !self.isActive else { return }
            self.capsule.isHidden = true
            self.capsule.transform = .identity
        }
    }
}

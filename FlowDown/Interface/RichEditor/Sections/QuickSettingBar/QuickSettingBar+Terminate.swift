//
//  QuickSettingBar+Terminate.swift
//  RichEditor
//

import UIKit

extension QuickSettingBar {
    private static let terminateHiddenScale = CGAffineTransform(scaleX: 0.92, y: 0.92)

    func configureTerminateButton() {
        terminateButton.iconView.image = UIImage(systemName: "stop.circle")?
            .withRenderingMode(.alwaysTemplate)
        terminateButton.isAccessibilityElement = true
        terminateButton.accessibilityLabel = NSLocalizedString("Terminate", comment: "")
        terminateButton.accessibilityTraits = .button
        terminateButton.isHidden = true
        terminateButton.actionBlock = { [weak self] in
            self?.handleTerminateTapped()
        }
    }

    /// Follows the displayed conversation's execution state. Pass `animated: false`
    /// when the conversation itself changes, so the new state is simply in place.
    func setTerminateVisible(_ visible: Bool, animated: Bool = true) {
        let changed = visible != isTerminateVisible
        guard changed || !animated else { return }

        guard animated, isOpen, window != nil, bounds.width > 0 else {
            applyTerminateVisibilityImmediately(visible, changed: changed)
            return
        }

        // Pending changes such as a new model name must not join this animation.
        layoutIfNeeded()

        terminateTransitionID += 1
        let transitionID = terminateTransitionID
        isTerminateVisible = visible
        needsTerminateReveal = visible
        needsTerminateRestore = !visible
        setTerminateInteractive(visible)

        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if visible, terminateButton.isHidden {
            prepareTerminateButtonForAppearance(reduceMotion: reduceMotion)
        }
        if reduceMotion {
            UIView.performWithoutAnimation {
                terminateButton.transform = .identity
                setNeedsLayout()
                layoutIfNeeded()
            }
        }

        let options: UIView.AnimationOptions = [.beginFromCurrentState, .allowUserInteraction]
        let animations = { [self] in
            terminateButton.alpha = visible ? 1 : 0
            if !reduceMotion {
                terminateButton.transform = visible ? .identity : Self.terminateHiddenScale
                setNeedsLayout()
                layoutIfNeeded()
            }
        }
        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self,
                  transitionID == terminateTransitionID,
                  !isTerminateVisible
            else { return }
            terminateButton.isHidden = true
            terminateButton.transform = .identity
        }

        if reduceMotion {
            UIView.animate(
                withDuration: 0.15,
                delay: 0,
                options: options.union(.curveLinear),
                animations: animations,
                completion: completion,
            )
        } else {
            // Critically damped spring: smooth settle, no overshoot, and a
            // reversal mid-flight continues from the current presentation.
            UIView.animate(
                springDuration: visible ? 0.38 : 0.3,
                bounce: 0,
                initialSpringVelocity: 0,
                delay: 0,
                options: options,
                animations: animations,
                completion: completion,
            )
        }
    }

    /// Places a laid-out button by `bounds` and `center`: its width lands at once
    /// while an enclosing animation moves only its position, and a transform in
    /// flight is left alone.
    func place(_ button: BlockButton, x: CGFloat, size: CGSize) {
        let center = CGPoint(x: x + size.width / 2, y: size.height / 2)
        let isFirstPlacement = button.bounds.isEmpty
        UIView.performWithoutAnimation {
            button.bounds = CGRect(origin: .zero, size: size)
            if isFirstPlacement { button.center = center }
            button.layoutIfNeeded()
        }
        if !isFirstPlacement { button.center = center }
    }

    /// Reveals the button once after it appears, returns the row to its leading
    /// edge once after it hides, and otherwise keeps the offset in range.
    /// Never touches a scroll the user is performing.
    func updateScrollOffsetAfterLayout() {
        let isUserScrolling = scrollView.isTracking || scrollView.isDragging || scrollView.isDecelerating
        let maxOffset = max(0, scrollView.contentSize.width - scrollView.bounds.width)
        defer {
            needsTerminateReveal = false
            needsTerminateRestore = false
        }
        guard !isUserScrolling else { return }

        let target: CGFloat = if needsTerminateReveal {
            maxOffset
        } else if needsTerminateRestore {
            0
        } else {
            min(max(scrollView.contentOffset.x, 0), maxOffset)
        }
        if scrollView.contentOffset.x != target {
            scrollView.contentOffset.x = target
        }
    }

    private func handleTerminateTapped() {
        guard isTerminateVisible, terminateButton.isEnabled else { return }
        setTerminateInteractive(false)
        terminateAction()
    }

    private func setTerminateInteractive(_ interactive: Bool) {
        terminateButton.isEnabled = interactive
        terminateButton.isUserInteractionEnabled = interactive
    }

    private func prepareTerminateButtonForAppearance(reduceMotion: Bool) {
        let previousButton = buttons.last { $0 !== terminateButton && !$0.isHidden }
        let x = previousButton.map { $0.center.x + $0.bounds.width / 2 + 10 } ?? horizontalAdjustment
        UIView.performWithoutAnimation {
            terminateButton.transform = .identity
            place(terminateButton, x: x, size: terminateButton.intrinsicContentSize)
            terminateButton.alpha = 0
            terminateButton.transform = reduceMotion ? .identity : Self.terminateHiddenScale
            terminateButton.isHidden = false
        }
    }

    private func applyTerminateVisibilityImmediately(_ visible: Bool, changed: Bool) {
        terminateTransitionID += 1
        isTerminateVisible = visible
        if changed { needsTerminateReveal = visible }
        if !visible {
            // Also on an unchanged hide: a conversation switch starts at the leading edge.
            needsTerminateReveal = false
            needsTerminateRestore = true
        } else {
            needsTerminateRestore = false
        }
        setTerminateInteractive(visible)

        buttons.forEach { $0.layer.removeAllAnimations() }
        scrollView.layer.removeAllAnimations()
        UIView.performWithoutAnimation {
            terminateButton.transform = .identity
            terminateButton.alpha = 1
            terminateButton.isHidden = !visible
            setNeedsLayout()
            layoutIfNeeded()
        }
    }
}

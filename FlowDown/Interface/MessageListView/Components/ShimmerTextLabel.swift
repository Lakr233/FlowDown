//
//  ShimmerTextLabel.swift
//  FlowDown
//
//  Created by Willow Zhang on 11/14/25
//

import UIKit

/// A label that displays text with an animated shimmer effect that sweeps across characters
final class ShimmerTextLabel: UILabel {
    // MARK: - Private Properties

    private var isAnimating = false
    private let gradientLayer = CAGradientLayer()
    private var originalTextColor: UIColor?
    private var cachedIntrinsicSize: CGSize?

    /// The size of the shimmer band (0.3 = 30% of the view width)
    private let bandSize: CGFloat = 0.3
    /// The alpha of the shimmer edges
    private let minimumAlpha: CGFloat = 0.3
    /// The alpha of the shimmer center
    private let maximumAlpha: CGFloat = 1.0
    /// Position of the bright spot within the band (0.0 - 1.0)
    private let gradientCenterLocation: CGFloat = 0.5

    // MARK: - Customizable Parameters

    /// Controls the shimmer animation speed (duration for one complete cycle)
    var animationDuration: TimeInterval = 1.5

    override var intrinsicContentSize: CGSize {
        // Use cached size during animation to prevent incorrect sizing when textColor is clear
        if isAnimating, let cached = cachedIntrinsicSize {
            return cached
        }
        return super.intrinsicContentSize
    }

    override var text: String? {
        didSet {
            // When text changes during animation, refresh cached size so layout can expand
            if isAnimating {
                cachedIntrinsicSize = super.intrinsicContentSize
                invalidateIntrinsicContentSize()
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupGradientLayer()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if window != nil, isAnimating {
            startShimmerAnimation()
        } else {
            gradientLayer.removeAllAnimations()
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if isAnimating {
            // If cached size is zero width (started shimmer before text assigned), fix it now
            if let cached = cachedIntrinsicSize, cached.width == 0 {
                let real = super.intrinsicContentSize
                if real.width > 0 { cachedIntrinsicSize = real }
            }
            gradientLayer.frame = bounds
            updateMaskForCurrentBoundsIfNeeded()
        }
    }

    private func setupGradientLayer() {
        gradientLayer.startPoint = CGPoint(x: -bandSize, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)

        updateGradientColors()
    }

    private func updateGradientColors() {
        let baseColor = originalTextColor ?? textColor ?? .label

        // Smooth gradient: dark -> bright -> dark
        gradientLayer.colors = [
            baseColor.withAlphaComponent(minimumAlpha).cgColor,
            baseColor.withAlphaComponent(maximumAlpha).cgColor,
            baseColor.withAlphaComponent(minimumAlpha).cgColor,
        ]

        gradientLayer.locations = [
            0,
            NSNumber(value: gradientCenterLocation),
            1,
        ]
    }

    /// Start the shimmer animation
    func startShimmer() {
        guard !isAnimating else { return }

        // Cache intrinsic size before changing text color
        cachedIntrinsicSize = super.intrinsicContentSize

        isAnimating = true

        // Save original text color
        originalTextColor = textColor

        // Update gradient colors
        updateGradientColors()

        // Hide original text, display via gradient layer + mask
        textColor = .clear
        gradientLayer.frame = bounds
        layer.addSublayer(gradientLayer)

        // Use text as mask
        if let maskLayer = createTextMaskLayer() {
            gradientLayer.mask = maskLayer
        }

        if window != nil {
            startShimmerAnimation()
        }
    }

    /// Stop the shimmer animation and return to normal state
    func stopShimmer() {
        isAnimating = false
        gradientLayer.removeAllAnimations()
        gradientLayer.removeFromSuperlayer()
        gradientLayer.mask = nil
        textColor = originalTextColor ?? .label
        originalTextColor = nil
        cachedIntrinsicSize = nil
    }

    private func createTextMaskLayer() -> CALayer? {
        guard let text, !text.isEmpty, bounds.width > 0, bounds.height > 0 else { return nil }

        // Render text to image using UIGraphicsImageRenderer
        let renderer = UIGraphicsImageRenderer(size: bounds.size)
        let image = renderer.image { _ in
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.alignment = textAlignment

            let attributes: [NSAttributedString.Key: Any] = [
                .font: font as Any,
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraphStyle,
            ]

            let textRect = CGRect(origin: .zero, size: bounds.size)
            (text as NSString).draw(in: textRect, withAttributes: attributes)
        }

        let maskLayer = CALayer()
        maskLayer.frame = bounds
        maskLayer.contents = image.cgImage
        maskLayer.contentsScale = UIScreen.main.scale

        return maskLayer
    }

    private func updateMaskForCurrentBoundsIfNeeded() {
        guard isAnimating else { return }
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard let maskLayer = createTextMaskLayer() else { return }

        gradientLayer.mask = maskLayer
    }

    private func startShimmerAnimation() {
        gradientLayer.removeAllAnimations()

        let min = -bandSize
        let max: CGFloat = 1 + bandSize

        let startPointAnimation = CABasicAnimation(keyPath: "startPoint")
        startPointAnimation.fromValue = CGPoint(x: min, y: 0.5)
        startPointAnimation.toValue = CGPoint(x: max, y: 0.5)

        let endPointAnimation = CABasicAnimation(keyPath: "endPoint")
        endPointAnimation.fromValue = CGPoint(x: 0, y: 0.5)
        endPointAnimation.toValue = CGPoint(x: max + bandSize, y: 0.5)

        let group = CAAnimationGroup()
        group.animations = [startPointAnimation, endPointAnimation]
        group.duration = animationDuration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)

        gradientLayer.add(group, forKey: "shimmer")
    }
}

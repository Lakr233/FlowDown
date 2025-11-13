//
//  ShimmerTextLabel.swift
//  FlowDown
//
//  Created by Willow Zhang on 11/14/25
//

import UIKit

/// A label that displays text with an animated shimmer effect that sweeps across characters
final class ShimmerTextLabel: UILabel {
    // MARK: - Direction Configuration

    /// Shimmer animation direction
    enum ShimmerDirection {
        case leftToRight
        case rightToLeft
        case topToBottom
        case bottomToTop
    }

    // MARK: - Private Properties

    private var isAnimating = false
    private let gradientLayer = CAGradientLayer()
    private var originalTextColor: UIColor?
    private var cachedIntrinsicSize: CGSize?

    // MARK: - Customizable Parameters

    /// Controls the shimmer animation speed (duration for one complete cycle)
    var animationDuration: TimeInterval = 1.5

    /// The size of the shimmer band (0.3 = 30% of the view width)
    var bandSize: CGFloat = 0.3 {
        didSet {
            if isAnimating {
                setupGradientLayer()
                if window != nil {
                    startShimmerAnimation()
                }
            }
        }
    }

    /// The minimum alpha/transparency of the shimmer effect (0.0 - 1.0)
    var minimumAlpha: CGFloat = 0.3 {
        didSet {
            minimumAlpha = max(0, min(1, minimumAlpha))
            if isAnimating {
                updateGradientColors()
            }
        }
    }

    /// The maximum alpha/transparency of the shimmer effect (0.0 - 1.0)
    var maximumAlpha: CGFloat = 1.0 {
        didSet {
            maximumAlpha = max(0, min(1, maximumAlpha))
            if isAnimating {
                updateGradientColors()
            }
        }
    }

    /// Custom shimmer color (if nil, uses text color)
    var shimmerColor: UIColor? {
        didSet {
            if isAnimating {
                updateGradientColors()
            }
        }
    }

    /// Shimmer animation direction
    var shimmerDirection: ShimmerDirection = .leftToRight {
        didSet {
            if isAnimating {
                setupGradientLayer()
                if window != nil {
                    startShimmerAnimation()
                }
            }
        }
    }

    /// Animation timing function
    var timingFunction: CAMediaTimingFunctionName = .linear {
        didSet {
            if isAnimating {
                gradientLayer.removeAllAnimations()
                if window != nil {
                    startShimmerAnimation()
                }
            }
        }
    }

    /// Gradient color positions (center position of the bright spot, 0.0 - 1.0)
    var gradientCenterLocation: CGFloat = 0.5 {
        didSet {
            gradientCenterLocation = max(0, min(1, gradientCenterLocation))
            if isAnimating {
                updateGradientColors()
            }
        }
    }

    /// Whether to use smooth fade at gradient edges
    var useFadeEdges: Bool = true {
        didSet {
            if isAnimating {
                updateGradientColors()
            }
        }
    }

    override var intrinsicContentSize: CGSize {
        // Use cached size during animation to prevent incorrect sizing when textColor is clear
        if isAnimating, let cached = cachedIntrinsicSize {
            return cached
        }
        return super.intrinsicContentSize
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
            gradientLayer.frame = bounds
        }
    }

    private func setupGradientLayer() {
        // Configure gradient direction based on shimmerDirection
        switch shimmerDirection {
        case .leftToRight:
            gradientLayer.startPoint = CGPoint(x: -bandSize, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
        case .rightToLeft:
            gradientLayer.startPoint = CGPoint(x: 1 + bandSize, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        case .topToBottom:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: -bandSize)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 0)
        case .bottomToTop:
            gradientLayer.startPoint = CGPoint(x: 0.5, y: 1 + bandSize)
            gradientLayer.endPoint = CGPoint(x: 0.5, y: 1)
        }

        updateGradientColors()
    }

    private func updateGradientColors() {
        // Use custom shimmer color or fallback to text color
        let baseColor = shimmerColor ?? originalTextColor ?? textColor ?? .label

        // Create gradient with customizable alpha values
        if useFadeEdges {
            // Smooth gradient: dark -> bright -> dark
            gradientLayer.colors = [
                baseColor.withAlphaComponent(minimumAlpha).cgColor,
                baseColor.withAlphaComponent(maximumAlpha).cgColor,
                baseColor.withAlphaComponent(minimumAlpha).cgColor,
            ]

            // Use gradientCenterLocation to control where the bright spot appears
            let edgeWidth = (1.0 - gradientCenterLocation) * 0.5
            gradientLayer.locations = [
                0,
                NSNumber(value: gradientCenterLocation),
                1,
            ]
        } else {
            // Sharp edges: no fade
            gradientLayer.colors = [
                baseColor.withAlphaComponent(maximumAlpha).cgColor,
                baseColor.withAlphaComponent(maximumAlpha).cgColor,
            ]

            gradientLayer.locations = [0, 1]
        }
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
        guard let text, !text.isEmpty else { return nil }
        
        // Validate bounds to prevent crash with zero or invalid size
        guard bounds.width > 0, bounds.height > 0 else { return nil }

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

    private func startShimmerAnimation() {
        gradientLayer.removeAllAnimations()

        let min = -bandSize
        let max: CGFloat = 1 + bandSize

        // Configure animation based on direction
        let startPointAnimation = CABasicAnimation(keyPath: "startPoint")
        let endPointAnimation = CABasicAnimation(keyPath: "endPoint")

        switch shimmerDirection {
        case .leftToRight:
            startPointAnimation.fromValue = CGPoint(x: min, y: 0.5)
            startPointAnimation.toValue = CGPoint(x: max, y: 0.5)
            endPointAnimation.fromValue = CGPoint(x: 0, y: 0.5)
            endPointAnimation.toValue = CGPoint(x: max + bandSize, y: 0.5)

        case .rightToLeft:
            startPointAnimation.fromValue = CGPoint(x: max, y: 0.5)
            startPointAnimation.toValue = CGPoint(x: min, y: 0.5)
            endPointAnimation.fromValue = CGPoint(x: 1, y: 0.5)
            endPointAnimation.toValue = CGPoint(x: min - bandSize, y: 0.5)

        case .topToBottom:
            startPointAnimation.fromValue = CGPoint(x: 0.5, y: min)
            startPointAnimation.toValue = CGPoint(x: 0.5, y: max)
            endPointAnimation.fromValue = CGPoint(x: 0.5, y: 0)
            endPointAnimation.toValue = CGPoint(x: 0.5, y: max + bandSize)

        case .bottomToTop:
            startPointAnimation.fromValue = CGPoint(x: 0.5, y: max)
            startPointAnimation.toValue = CGPoint(x: 0.5, y: min)
            endPointAnimation.fromValue = CGPoint(x: 0.5, y: 1)
            endPointAnimation.toValue = CGPoint(x: 0.5, y: min - bandSize)
        }

        // Combine animations
        let group = CAAnimationGroup()
        group.animations = [startPointAnimation, endPointAnimation]
        group.duration = animationDuration
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: timingFunction)

        gradientLayer.add(group, forKey: "shimmer")
    }
}

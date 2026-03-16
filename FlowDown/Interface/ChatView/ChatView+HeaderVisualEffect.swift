//
//  ChatView+HeaderVisualEffect.swift
//  FlowDown
//
//  Created by GitHub Copilot on 2026/3/15.
//

import UIKit

private struct ChatHeaderBlurGradient: Equatable {
    let height: CGFloat
    let alpha: [CGFloat]
    let positions: [CGFloat]
}

private func generateChatHeaderImage(
    _ size: CGSize,
    opaque: Bool = false,
    scale: CGFloat = 0,
    draw: (CGSize, CGContext) -> Void
) -> UIImage? {
    guard size.width > 0, size.height > 0 else {
        return nil
    }

    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = opaque
    if scale > 0 {
        format.scale = scale
    }

    let renderer = UIGraphicsImageRenderer(size: size, format: format)
    return renderer.image { context in
        draw(size, context.cgContext)
    }
}

private func generateChatHeaderGradientImage(
    size: CGSize,
    colors: [UIColor],
    locations: [CGFloat],
    isInverted: Bool = false
) -> UIImage? {
    guard colors.count == locations.count, !colors.isEmpty else {
        return nil
    }

    return generateChatHeaderImage(size, opaque: false) { size, context in
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let gradientColors = colors.map(\.cgColor) as CFArray
        var gradientLocations = locations
        guard let gradient = CGGradient(
            colorsSpace: colorSpace,
            colors: gradientColors,
            locations: &gradientLocations
        ) else {
            return
        }

        if isInverted {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: size.height),
                end: CGPoint(x: 0, y: 0),
                options: []
            )
        } else {
            context.drawLinearGradient(
                gradient,
                start: CGPoint(x: 0, y: 0),
                end: CGPoint(x: 0, y: size.height),
                options: []
            )
        }
    }
}

private enum ChatHeaderEdgeCurve {
    static func gradient(baseHeight: CGFloat) -> ChatHeaderBlurGradient {
        let sampleCount = max(24, min(96, Int(baseHeight.rounded(.up)) * 2))
        let positions = (0..<sampleCount).map { index in
            CGFloat(index) / CGFloat(sampleCount - 1)
        }
        let alpha = positions.map { position in
            let eased = smoothstep(position)
            return peakAlpha * pow(max(0, 1 - eased), tailExponent)
        }

        return ChatHeaderBlurGradient(
            height: baseHeight,
            alpha: alpha,
            positions: positions
        )
    }

    private static let peakAlpha: CGFloat = 0.85
    private static let tailExponent: CGFloat = 1.15

    private static func smoothstep(_ value: CGFloat) -> CGFloat {
        let clamped = min(max(value, 0), 1)
        return clamped * clamped * (3 - 2 * clamped)
    }
}

final class ChatHeaderGlassBackgroundContainerView: UIView {
    private let backgroundView: UIView
    private let _contentView: UIView
    private let effectView: UIVisualEffectView?
    private let enabledEffect: UIVisualEffect?
    private let legacyGlassView: LegacyGlassBackdropView?

    var contentView: UIView { _contentView }

    override init(frame: CGRect) {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            let effect = UIGlassContainerEffect()
            effect.spacing = 7.0
            let effectView = UIVisualEffectView(effect: effect)
            backgroundView = effectView
            _contentView = effectView.contentView
            self.effectView = effectView
            enabledEffect = effect
            legacyGlassView = nil
        } else {
            let legacyGlass = LegacyGlassBackdropView(blurRadius: 4.0, showsBorder: false)
            backgroundView = legacyGlass
            _contentView = legacyGlass.contentView
            effectView = nil
            enabledEffect = nil
            legacyGlassView = legacyGlass
        }

        super.init(frame: frame)
        addSubview(backgroundView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        backgroundView.frame = bounds
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if alpha.isZero || isHidden || !isUserInteractionEnabled {
            return nil
        }

        for view in contentView.subviews.reversed() {
            let convertedPoint = convert(point, to: view)
            if let result = view.hitTest(convertedPoint, with: event), result.isUserInteractionEnabled {
                return result
            }
        }

        let result = contentView.hitTest(convert(point, to: contentView), with: event)
        if result === contentView {
            return nil
        }
        return result
    }

    func update(isDark: Bool) {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            backgroundView.overrideUserInterfaceStyle = isDark ? .dark : .light
        }
    }

    func setVisualEffectEnabled(_ isEnabled: Bool) {
        effectView?.effect = isEnabled ? enabledEffect : nil
        legacyGlassView?.setEffectEnabled(isEnabled)
    }

    func setContentTopOffset(_ offset: CGFloat) {
        legacyGlassView?.contentTopOffset = offset
    }
}

private final class ChatHeaderVariableBlurView: UIView {
    private struct Params: Equatable {
        let size: CGSize
        let constantHeight: CGFloat
        let isInverted: Bool
        let gradient: ChatHeaderBlurGradient
    }

    private let blurView: PrivateBlurEngine.MaskedBlurView
    private var params: Params?

    init(maxBlurRadius: CGFloat = 20) {
        blurView = PrivateBlurEngine.MaskedBlurView(maxBlurRadius: maxBlurRadius)
        super.init(frame: .zero)
        addSubview(blurView)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        blurView.frame = bounds
    }

    func update(size: CGSize, constantHeight: CGFloat, isInverted: Bool, gradient: ChatHeaderBlurGradient) {
        let params = Params(
            size: size,
            constantHeight: constantHeight,
            isInverted: isInverted,
            gradient: gradient
        )
        guard params != self.params else {
            return
        }

        self.params = params
        blurView.frame = CGRect(origin: .zero, size: size)
        blurView.update(
            size: size,
            maskImage: Self.makeMaskImage(
                size: size,
                constantHeight: constantHeight,
                isInverted: isInverted,
                gradient: gradient
            )
        )
    }

    private static func makeMaskImage(
        size: CGSize,
        constantHeight: CGFloat,
        isInverted: Bool,
        gradient: ChatHeaderBlurGradient
    ) -> UIImage? {
        guard size.width > 0, size.height > 0 else {
            return nil
        }

        let gradientHeight = min(size.height, max(1.0, constantHeight))
        let gradientImage = ChatHeaderEdgeEffectView.generateEdgeGradient(
            baseHeight: max(1.0, gradient.height),
            isInverted: isInverted
        )

        return generateChatHeaderImage(size, opaque: false) { size, context in
            let fullBounds = CGRect(origin: .zero, size: size)
            context.clear(fullBounds)

            let gradientFrame: CGRect
            let solidFrame: CGRect

            if isInverted {
                gradientFrame = CGRect(
                    origin: .zero,
                    size: CGSize(width: size.width, height: gradientHeight)
                )
                solidFrame = CGRect(
                    origin: CGPoint(x: 0, y: gradientHeight),
                    size: CGSize(width: size.width, height: max(0, size.height - gradientHeight))
                )
            } else {
                gradientFrame = CGRect(
                    origin: CGPoint(x: 0, y: size.height - gradientHeight),
                    size: CGSize(width: size.width, height: gradientHeight)
                )
                solidFrame = CGRect(
                    origin: .zero,
                    size: CGSize(width: size.width, height: max(0, size.height - gradientHeight))
                )
            }

            context.setFillColor(UIColor(white: 0, alpha: 1).cgColor)
            context.fill(solidFrame)

            UIGraphicsPushContext(context)
            gradientImage.draw(in: gradientFrame, blendMode: .normal, alpha: 1)
            UIGraphicsPopContext()
        }
    }
}

final class ChatHeaderEdgeEffectView: UIView {
    enum Edge: Equatable {
        case top
        case bottom
    }

    private let contentView = UIView()
    private let contentMaskView = UIImageView()
    private var blurView: ChatHeaderVariableBlurView?
    private var currentMaskSignature: MaskSignature?

    private struct MaskSignature: Equatable {
        let edge: Edge
        let height: CGFloat
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.mask = contentMaskView
        addSubview(contentView)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateColor(_ color: UIColor) {
        contentView.backgroundColor = color
    }

    func update(content: UIColor?, blur: Bool, alpha: CGFloat, rect: CGRect, edge: Edge, edgeSize: CGFloat, contentTopOffset: CGFloat = 0) {
        if let content {
            contentView.backgroundColor = content
        }
        contentView.alpha = alpha

        let bounds = CGRect(origin: .zero, size: rect.size)
        frame = rect

        let contentFrame = CGRect(
            x: 0,
            y: contentTopOffset,
            width: bounds.width,
            height: max(0, bounds.height - contentTopOffset)
        )
        contentView.frame = contentFrame
        contentMaskView.frame = CGRect(origin: .zero, size: contentFrame.size)

        let maskSignature = MaskSignature(edge: edge, height: edgeSize)
        if currentMaskSignature != maskSignature {
            currentMaskSignature = maskSignature
            if edgeSize > 0 {
                contentMaskView.image = Self.generateEdgeGradient(baseHeight: edgeSize, isInverted: edge == .bottom)
            } else {
                contentMaskView.image = nil
            }
        }

        if blur {
            let blurHeight = max(edgeSize, bounds.height - 14)
            let blurFrame = CGRect(
                origin: CGPoint(x: 0, y: edge == .bottom ? (bounds.height - blurHeight) : 0),
                size: CGSize(width: bounds.width, height: blurHeight)
            )

            let blurView: ChatHeaderVariableBlurView
            if let current = self.blurView {
                blurView = current
            } else {
                blurView = ChatHeaderVariableBlurView(maxBlurRadius: 1.0)
                insertSubview(blurView, at: 0)
                self.blurView = blurView
            }

            blurView.update(
                size: blurFrame.size,
                constantHeight: max(1.0, edgeSize - 4.0),
                isInverted: edge == .bottom,
                gradient: Self.generateEdgeGradientData(baseHeight: max(1.0, edgeSize - 4.0))
            )
            blurView.frame = blurFrame
            blurView.transform = contentMaskView.transform
        } else if let blurView = self.blurView {
            self.blurView = nil
            blurView.removeFromSuperview()
        }
    }

    private static func generateEdgeGradientData(baseHeight: CGFloat) -> ChatHeaderBlurGradient {
        ChatHeaderEdgeCurve.gradient(baseHeight: baseHeight)
    }

    static func generateEdgeGradient(baseHeight: CGFloat, isInverted: Bool) -> UIImage {
        let gradientData = generateEdgeGradientData(baseHeight: baseHeight)
        let colors = gradientData.alpha.map { UIColor(white: 0, alpha: $0) }
        return generateChatHeaderGradientImage(
            size: CGSize(width: 1.0, height: baseHeight),
            colors: colors,
            locations: gradientData.positions,
            isInverted: isInverted
        )!.resizableImage(
            withCapInsets: UIEdgeInsets(
                top: isInverted ? baseHeight : 0,
                left: 0,
                bottom: isInverted ? 0 : baseHeight,
                right: 0
            ),
            resizingMode: .stretch
        )
    }
}

//
//  FloatingChrome.swift
//  FlowDown
//
//  The bars' chrome without a bar background: a soft progressive edge
//  (`ProgressiveBlurView`) under the title row, and buttons that carry their
//  own surface — system glass on iOS 26 and later, a material circle before.
//  Designer spec v2 (Colo, header-fade-blur.md).
//

import SnapKit
import UIKit

enum FloatingChrome {
    /// How far the solid part of the top edge runs past the bottom of the
    /// header buttons.
    static let belowButtons: CGFloat = 14
    /// How far past that the edge fades out.
    static let tail: CGFloat = 28
    /// The circle every icon button stands in.
    static let buttonSize: CGFloat = 44
    /// The icon inside it.
    static let iconConfiguration = UIImage.SymbolConfiguration(pointSize: 17, weight: .medium)
    /// From the screen or column edge to the nearest button.
    static let edgeInset: CGFloat = 16
    /// Between two buttons side by side.
    static let buttonSpacing: CGFloat = 8

    /// The top edge's height: from the top of the screen to the bottom of the
    /// header buttons, then `belowButtons` and the `tail`.
    static func topEdgeHeight(buttonBottom: CGFloat) -> CGFloat {
        max(0, buttonBottom) + fadeLength
    }

    /// How far an edge fades out, past the buttons on top and above the
    /// input card at the bottom.
    static let fadeLength: CGFloat = belowButtons + tail

    /// The edges' numbers (designer, Colo, 2026-11-10). The vendored
    /// `.standard` is tuned for a title in its own capsule; here the title
    /// stands straight on the content, so the edge holds full strength from
    /// the screen edge to the buttons (or the input card) and fades only
    /// over the last `fadeLength`, with a stronger blur and frost.
    static func edgeStyle(height: CGFloat) -> ProgressiveBlurStyle {
        var style = ProgressiveBlurStyle.standard
        style.radius = 6
        style.frostRadius = 16
        style.frostOpacity = 0.45
        style.hold = height > fadeLength ? (height - fadeLength) / height : 0
        return style
    }

    #if DEBUG
        /// Launch with `FD_FORCE_LEGACY_CHROME=1` to draw the buttons the way
        /// iOS 17–25 does on a newer system — the Team has no simulator older
        /// than iOS 26 (`simulator launch <id> --env FD_FORCE_LEGACY_CHROME=1`).
        /// Debug builds only; it changes the buttons, not the edge.
        static let forcesLegacyButtons = ProcessInfo.processInfo.environment["FD_FORCE_LEGACY_CHROME"] == "1"
    #else
        static let forcesLegacyButtons = false
    #endif

    /// Whether buttons stand in the system's glass (iOS 26 and later) or in
    /// the material circle of earlier systems.
    static var usesSystemGlass: Bool {
        #if targetEnvironment(macCatalyst)
            return false
        #else
            if forcesLegacyButtons { return false }
            if #available(iOS 26, *) { return true }
            return false
        #endif
    }

    /// Turns off the system's own top scroll edge on iOS 26 and later: under
    /// the progressive edge the two stack into a band again.
    static func hideSystemTopEdge(of scrollView: UIScrollView) {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                scrollView.topEdgeEffect.isHidden = true
            }
        #endif
    }

    /// The same for the bottom edge, where the input bar wears its own.
    static func hideSystemBottomEdge(of scrollView: UIScrollView) {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                scrollView.bottomEdgeEffect.isHidden = true
            }
        #endif
    }
}

extension ProgressiveBlurView {
    /// Places the edge and gives it `FloatingChrome.edgeStyle` for that
    /// height, so the fade is always `fadeLength` long.
    func layoutAsBarEdge(_ frame: CGRect) {
        self.frame = frame
        let style = FloatingChrome.edgeStyle(height: frame.height)
        if self.style != style { self.style = style }
    }
}

// MARK: - Surface

extension UIView {
    /// Stands the view in a floating button's surface: interactive glass on
    /// iOS 26 and later, `FloatingButtonSurfaceView` before. The view fills
    /// the surface; the surface takes the size its constraints give it.
    func wrappedInFloatingButtonSurface() -> UIView {
        #if !targetEnvironment(macCatalyst)
            if FloatingChrome.usesSystemGlass, #available(iOS 26, *) {
                let effect = UIGlassEffect()
                effect.isInteractive = true
                let container = UIVisualEffectView(effect: effect)
                container.clipsToBounds = true
                container.cornerConfiguration = .capsule()
                container.contentView.addSubview(self)
                snp.makeConstraints { $0.edges.equalToSuperview() }
                return container
            }
        #endif
        let container = FloatingButtonSurfaceView()
        container.contentView.addSubview(self)
        snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }
}

/// A floating button's surface before iOS 26: a regular-material capsule
/// (a circle when square) with a hairline edge and a soft shadow, pressed to
/// 0.92 while touched.
final class FloatingButtonSurfaceView: UIView, UIGestureRecognizerDelegate {
    let contentView = UIView()
    private let materialView = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))

    init() {
        super.init(frame: .zero)
        clipsToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowRadius = 10

        materialView.clipsToBounds = true
        materialView.layer.cornerCurve = .continuous
        materialView.layer.borderWidth = 0.5
        addSubview(materialView)
        materialView.contentView.addSubview(contentView)

        let press = UILongPressGestureRecognizer(target: self, action: #selector(handlePress(_:)))
        press.minimumPressDuration = 0
        press.cancelsTouchesInView = false
        press.delaysTouchesBegan = false
        press.delegate = self
        addGestureRecognizer(press)

        updateAppearance()
        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: FloatingButtonSurfaceView, _: UITraitCollection) in
            view.updateAppearance()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        materialView.frame = bounds
        contentView.frame = materialView.contentView.bounds
        let radius = min(bounds.width, bounds.height) / 2
        materialView.layer.cornerRadius = radius
        layer.shadowPath = UIBezierPath(roundedRect: bounds, cornerRadius: radius).cgPath
    }

    private func updateAppearance() {
        let isDark = traitCollection.userInterfaceStyle == .dark
        materialView.layer.borderColor = isDark
            ? UIColor.white.withAlphaComponent(0.12).cgColor
            : UIColor.black.withAlphaComponent(0.08).cgColor
        layer.shadowOpacity = isDark ? 0.3 : 0.1
    }

    @objc private func handlePress(_ recognizer: UILongPressGestureRecognizer) {
        let pressed: Bool
        switch recognizer.state {
        case .began:
            pressed = true
        case .changed:
            pressed = bounds.insetBy(dx: -16, dy: -16).contains(recognizer.location(in: self))
        default:
            pressed = false
        }
        let target: CGAffineTransform = pressed ? .init(scaleX: 0.92, y: 0.92) : .identity
        guard transform != target else { return }
        UIView.animate(
            springDuration: 0.25,
            bounce: 0,
            options: [.allowUserInteraction, .beginFromCurrentState],
        ) {
            self.transform = target
        }
    }

    func gestureRecognizer(_: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer) -> Bool {
        true
    }
}

// MARK: - Buttons

/// A 44 pt floating icon button: a 17 pt medium symbol in the primary colour
/// (never the accent), standing in `wrappedInFloatingButtonSurface()`.
final class FloatingIconButton: UIButton {
    var easyHitInsets: UIEdgeInsets = .init(top: -8, left: -8, bottom: -8, right: -8)

    convenience init(systemName: String) {
        self.init(image: UIImage(systemName: systemName, withConfiguration: FloatingChrome.iconConfiguration))
    }

    init(image: UIImage?) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        configuration.image = image
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .zero
        self.configuration = configuration
        tintColor = .label
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        .init(width: FloatingChrome.buttonSize, height: FloatingChrome.buttonSize)
    }

    override func point(inside point: CGPoint, with _: UIEvent?) -> Bool {
        bounds.inset(by: easyHitInsets).contains(point)
    }
}

/// A 44 pt high floating text button (Done, Cancel, Save…): 17 pt, semibold
/// when it confirms, 16 pt either side.
final class FloatingTextButton: UIButton {
    init(title: String, isConfirming: Bool) {
        super.init(frame: .zero)
        var configuration = UIButton.Configuration.plain()
        var attributed = AttributedString(title)
        attributed.font = .systemFont(ofSize: 17, weight: isConfirming ? .semibold : .regular)
        configuration.attributedTitle = attributed
        configuration.baseForegroundColor = .label
        configuration.contentInsets = .init(top: 0, leading: 16, bottom: 0, trailing: 16)
        configuration.titleLineBreakMode = .byTruncatingTail
        self.configuration = configuration
        tintColor = .label
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return .init(width: max(size.width, FloatingChrome.buttonSize), height: FloatingChrome.buttonSize)
    }
}

//
//  UIView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/2.
//

import SnapKit
import UIKit

// MARK: - Glass Effect

enum GlassEffectCornerStyle {
    case none
    case fixed(CGFloat)
    case capsule
}

extension UIView {
    func wrappedInGlassEffect(
        interactive: Bool = true,
        cornerStyle: GlassEffectCornerStyle = .none,
    ) -> UIView {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                let effect = UIGlassEffect()
                effect.isInteractive = interactive
                let container = UIVisualEffectView(effect: effect)
                container.clipsToBounds = true
                switch cornerStyle {
                case .none:
                    break
                case let .fixed(radius):
                    container.cornerConfiguration = .corners(radius: .fixed(radius))
                case .capsule:
                    container.cornerConfiguration = .capsule()
                }
                container.contentView.addSubview(self)
                snp.makeConstraints { $0.edges.equalToSuperview() }
                return container
            }
        #endif

        let container = LegacyGlassBackdropView(blurRadius: 4.0)
        switch cornerStyle {
        case .none:
            break
        case let .fixed(radius):
            container.layer.cornerRadius = radius
        case .capsule:
            container.setCapsuleCorners()
        }
        container.contentView.addSubview(self)
        snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }
}

extension UIVisualEffectView {
    static func adaptive(style: UIBlurEffect.Style = .systemMaterial) -> UIVisualEffectView {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                return UIVisualEffectView(effect: UIGlassEffect())
            }
        #endif
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }
}

// MARK: - Animation

extension UIView {
    func doWithAnimation(duration: TimeInterval = 0.5, _ execute: @escaping () -> Void, completion: @escaping () -> Void = {}) {
        layoutIfNeeded()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 1.0,
            // Without `beginFromCurrentState` a second call while the first is
            // still running throws away what is on screen and restarts from the
            // previous target, which nothing ever displayed. Anything driven
            // continuously, like dragging the sidebar divider, then jumps
            // backwards on every sample instead of retargeting smoothly.
            options: [.curveEaseInOut, .beginFromCurrentState, .allowUserInteraction],
        ) {
            execute()
            self.layoutIfNeeded()
        } completion: { _ in
            completion()
        }
    }

    func puddingAnimate() {
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()
        transform = CGAffineTransform(scaleX: 0.975, y: 0.975)
        layoutIfNeeded()
        doWithAnimation { self.transform = .identity }
    }

    func shake() {
        let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        animation.duration = 0.5
        animation.values = [-10, 10, -8, 8, -6, 6, -4, 4, 0]
        animation.isRemovedOnCompletion = true
        layer.add(animation, forKey: "shake")
    }
}

extension UIView {
    func hideKeyboardWhenTappedAround() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(UIView.dismissKeyboard))
        tap.cancelsTouchesInView = false
        addGestureRecognizer(tap)
    }

    @objc func dismissKeyboard() {
        endEditing(true)
    }
}

extension UIView {
    var nearestScrollView: UIScrollView? {
        var look: UIView = self
        while let superview = look.superview {
            look = superview
            if let scrollView = superview as? UIScrollView {
                return scrollView
            }
        }
        return nil
    }
}

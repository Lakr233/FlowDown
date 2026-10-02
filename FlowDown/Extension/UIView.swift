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
    case capsule
}

extension UIView {
    func wrappedInGlassEffect(cornerStyle: GlassEffectCornerStyle = .capsule) -> UIView {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26, *) {
                let effect = UIGlassEffect()
                effect.isInteractive = true
                let container = UIVisualEffectView(effect: effect)
                container.clipsToBounds = true
                switch cornerStyle {
                case .capsule:
                    container.cornerConfiguration = .capsule()
                }
                container.contentView.addSubview(self)
                snp.makeConstraints { $0.edges.equalToSuperview() }
                return container
            }
        #endif

        let container = LegacyGlassBackdropView()
        container.contentView.addSubview(self)
        snp.makeConstraints { $0.edges.equalToSuperview() }
        return container
    }
}

// MARK: - Animation

extension UIView {
    func doWithAnimation(
        duration: TimeInterval = 0.5,
        _ execute: @escaping () -> Void,
        completion: @escaping () -> Void = {}
    ) {
        layoutIfNeeded()
        UIView.animate(
            withDuration: duration,
            delay: 0,
            usingSpringWithDamping: 0.9,
            initialSpringVelocity: 1.0,
            // `allowUserInteraction` is what keeps a continuous gesture alive:
            // by default UIKit ignores input aimed at a hierarchy that is being
            // animated, so a drag that animates the layout on every sample gets
            // its own remaining events swallowed and freezes until the animation
            // ends. `beginFromCurrentState` then lets each new sample retarget
            // the animation already in flight, instead of discarding what is on
            // screen and restarting from a target nothing ever displayed.
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

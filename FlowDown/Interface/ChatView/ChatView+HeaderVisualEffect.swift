//
//  ChatView+HeaderVisualEffect.swift
//  FlowDown
//
//  Created by GitHub Copilot on 2026/3/15.
//

import UIKit

final class ChatHeaderGlassBackgroundContainerView: UIView {
    private let backgroundView: UIView
    private let _contentView: UIView
    private let effectView: UIVisualEffectView?
    private let enabledEffect: UIVisualEffect?

    var contentView: UIView {
        _contentView
    }

    override init(frame: CGRect) {
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26.0, *) {
                let effect = UIGlassContainerEffect()
                effect.spacing = 7.0
                let effectView = UIVisualEffectView(effect: effect)
                backgroundView = effectView
                _contentView = effectView.contentView
                self.effectView = effectView
                enabledEffect = effect
            } else {
                // The title bar's own regular-blur background and separator do the
                // separating; this container only hosts the bar content.
                let plain = UIView()
                backgroundView = plain
                _contentView = plain
                effectView = nil
                enabledEffect = nil
            }
        #else
            let plain = UIView()
            backgroundView = plain
            _contentView = plain
            effectView = nil
            enabledEffect = nil
        #endif

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
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 26.0, *) {
                backgroundView.overrideUserInterfaceStyle = isDark ? .dark : .light
            }
        #endif
    }

    func setVisualEffectEnabled(_ isEnabled: Bool) {
        effectView?.effect = isEnabled ? enabledEffect : nil
    }
}

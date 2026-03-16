//
//  LegacyGlassBackdropView.swift
//  FlowDown
//
//  Created by Codex on 2026/3/16.
//

import UIKit

final class LegacyGlassBackdropView: UIView {
    private let backdropLayer: CALayer?
    private let blurRadius: CGFloat
    private let showsBorder: Bool
    private let tintOverlay = UIView()
    private let hostedContentView = UIView()
    private var isCapsule = false
    private var isEffectEnabled = true
    var contentTopOffset: CGFloat = 0

    var contentView: UIView { hostedContentView }

    init(blurRadius: CGFloat = 4.0, showsBorder: Bool = true) {
        self.blurRadius = blurRadius
        self.showsBorder = showsBorder
        backdropLayer = PrivateBlurEngine.makeBackdropLayer()

        super.init(frame: .zero)

        layer.cornerCurve = .continuous
        clipsToBounds = true

        if let backdropLayer {
            layer.addSublayer(backdropLayer)
            PrivateBlurEngine.configureBackdropLayer(backdropLayer)
        }

        tintOverlay.backgroundColor = UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark
                ? UIColor(white: 1.0, alpha: 0.1)
                : UIColor(white: 1.0, alpha: 0.45)
        }
        addSubview(tintOverlay)
        addSubview(hostedContentView)

        if showsBorder {
            layer.borderWidth = 0.33
            updateBorderColor()
        }

        updateEffectAppearance()

        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LegacyGlassBackdropView, _: UITraitCollection) in
            view.updateBorderColor()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func setCapsuleCorners() {
        isCapsule = true
    }

    func setEffectEnabled(_ isEnabled: Bool) {
        guard isEffectEnabled != isEnabled else {
            return
        }

        isEffectEnabled = isEnabled
        updateEffectAppearance()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer?.frame = bounds
        CATransaction.commit()

        tintOverlay.frame = bounds

        if contentTopOffset > 0 {
            hostedContentView.frame = CGRect(
                x: 0,
                y: contentTopOffset,
                width: bounds.width,
                height: max(0, bounds.height - contentTopOffset)
            )
        } else {
            hostedContentView.frame = bounds
        }

        if isCapsule {
            layer.cornerRadius = min(bounds.width, bounds.height) / 2
        }
    }

    private func updateBorderColor() {
        guard layer.borderWidth > 0 else {
            return
        }

        layer.borderColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.2).cgColor
            : UIColor.black.withAlphaComponent(0.08).cgColor
    }

    private func updateEffectAppearance() {
        if isEffectEnabled,
           let blurFilter = PrivateBlurEngine.makeGaussianBlurFilter(radius: blurRadius)
        {
            backdropLayer?.filters = [blurFilter]
        } else {
            backdropLayer?.filters = nil
        }

        tintOverlay.alpha = isEffectEnabled ? 1 : 0
        layer.borderWidth = isEffectEnabled && showsBorder ? 0.33 : 0
        updateBorderColor()
    }
}

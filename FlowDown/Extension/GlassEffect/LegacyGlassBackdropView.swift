//
//  LegacyGlassBackdropView.swift
//  FlowDown
//
//  Created by Codex on 2026/3/16.
//

import UIKit

final class LegacyGlassBackdropView: UIView {
    private let backdropLayer: CALayer?
    private let tintOverlay = UIView()

    let contentView = UIView()

    init() {
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
        addSubview(contentView)

        if let blurFilter = PrivateBlurEngine.makeGaussianBlurFilter(radius: 4.0) {
            backdropLayer?.filters = [blurFilter]
        }

        layer.borderWidth = 0.33
        updateBorderColor()

        _ = registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: LegacyGlassBackdropView, _: UITraitCollection) in
            view.updateBorderColor()
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdropLayer?.frame = bounds
        CATransaction.commit()

        tintOverlay.frame = bounds

        contentView.frame = bounds

        layer.cornerRadius = min(bounds.width, bounds.height) / 2
    }

    private func updateBorderColor() {
        layer.borderColor = traitCollection.userInterfaceStyle == .dark
            ? UIColor.white.withAlphaComponent(0.2).cgColor
            : UIColor.black.withAlphaComponent(0.08).cgColor
    }
}

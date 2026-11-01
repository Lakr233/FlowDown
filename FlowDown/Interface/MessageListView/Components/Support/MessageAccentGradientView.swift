import UIKit

/// The user bubble's 10–15% accent gradient, shared by the image album.
///
/// The gradient is the view's own layer, so it follows the view's frame the
/// way UIKit moves views: at once outside an animation block, and never on
/// its own. A free-standing sublayer animates every frame change implicitly,
/// so a row out of the pool would slide its ground from the size its
/// previous message left it at.
final class MessageAccentGradientView: UIView {
    override class var layerClass: AnyClass {
        CAGradientLayer.self
    }

    private var gradient: CAGradientLayer {
        layer as! CAGradientLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        gradient.startPoint = CGPoint(x: 0.6, y: 0)
        gradient.endPoint = CGPoint(x: 0.4, y: 1)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateColors()
    }

    private func updateColors() {
        let accent = UIColor.accent.resolvedColor(with: traitCollection)
        gradient.colors = [accent.withAlphaComponent(0.10).cgColor, accent.withAlphaComponent(0.15).cgColor]
    }
}

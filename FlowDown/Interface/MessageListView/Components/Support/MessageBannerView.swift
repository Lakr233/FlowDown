import UIKit

/// One line under a status title, at the reading width, between hairlines on
/// a faint grey ground that runs the row's whole width. New text fades in,
/// at once under Reduce Motion.
final class MessageBannerView: UIView {
    static let height: CGFloat = 32

    private let label = UILabel()
    /// The grey ground and its hairlines, drawn past the view's own edges to
    /// the row's: the line keeps the reading width, its ground does not.
    private let ground = UIView()
    private let topRule = UIView()
    private let bottomRule = UIView()
    private var shown: String?

    /// How far the ground reaches past each side, set by the row.
    var groundBleed = UIEdgeInsets.zero {
        didSet {
            if groundBleed != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// How far the text sits inside the view on each side.
    var textInset: CGFloat = 0 {
        didSet {
            if textInset != oldValue {
                setNeedsLayout()
            }
        }
    }

    var font: UIFont = .preferredFont(forTextStyle: .footnote) {
        didSet { label.font = font }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        ground.backgroundColor = UIColor.systemGray.withAlphaComponent(0.05)
        addSubview(ground)
        for rule in [topRule, bottomRule] {
            rule.backgroundColor = .separator
            ground.addSubview(rule)
        }
        label.font = font
        label.textColor = .secondaryLabel
        label.numberOfLines = 1
        addSubview(label)
        isAccessibilityElement = true
        accessibilityTraits = .staticText
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    /// `animated`: the same row showing its next line.
    func show(_ text: String, truncatesHead: Bool = false, animated: Bool) {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        label.lineBreakMode = truncatesHead ? .byTruncatingHead : .byTruncatingTail
        guard line != shown else { return }
        let previous = shown
        shown = line
        label.layer.removeAllAnimations()
        label.text = line
        accessibilityLabel = line
        if animated, previous != nil, window != nil, !UIAccessibility.isReduceMotionEnabled {
            let fadeIn = CATransition()
            fadeIn.type = .fade
            fadeIn.duration = 0.2
            label.layer.add(fadeIn, forKey: "content")
        }
    }

    func reset() {
        shown = nil
        label.layer.removeAllAnimations()
        label.text = nil
        accessibilityLabel = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let rule = 1 / max(traitCollection.displayScale, 1)
        ground.frame = bounds.inset(
            by: UIEdgeInsets(top: 0, left: -groundBleed.left, bottom: 0, right: -groundBleed.right),
        )
        topRule.frame = CGRect(x: 0, y: 0, width: ground.bounds.width, height: rule)
        bottomRule.frame = CGRect(x: 0, y: ground.bounds.height - rule, width: ground.bounds.width, height: rule)
        label.frame = bounds.insetBy(dx: textInset, dy: 0)
    }
}

//
//  IconButton.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/16.
//

import UIKit

class IconButton: UIView {
    let imageView = UIImageView()

    var tapAction: () -> Void = {}

    /// A disabled button stays in place, greyed out, and ignores taps.
    var isEnabled = true {
        didSet {
            guard oldValue != isEnabled else { return }
            imageView.tintColor = isEnabled ? .label : .tertiaryLabel
            if isEnabled {
                accessibilityTraits.remove(.notEnabled)
            } else {
                accessibilityTraits.insert(.notEnabled)
            }
        }
    }

    required init() {
        super.init(frame: .zero)
        addSubview(imageView)
        imageView.tintColor = .label
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit

        let tap = UITapGestureRecognizer(target: self, action: #selector(buttonAction))
        addGestureRecognizer(tap)

        isUserInteractionEnabled = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    required convenience init(icon: String) {
        self.init()
        imageView.image = UIImage(named: icon)?
            .withRenderingMode(.alwaysTemplate)
    }

    func change(icon: String, animated: Bool = true) {
        if animated {
            UIView.transition(with: imageView, duration: 0.3, options: .transitionCrossDissolve, animations: {
                self.change(icon: icon, animated: false)
            }, completion: nil)
        } else {
            imageView.image = UIImage(named: icon)?
                .withRenderingMode(.alwaysTemplate)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds.insetBy(dx: 2, dy: 2)
    }

    @objc private func buttonAction() {
        guard isEnabled else { return }
        guard !isHidden else { return }
        guard alpha > 0 else { return }
        puddingAnimate()
        tapAction()
    }
}

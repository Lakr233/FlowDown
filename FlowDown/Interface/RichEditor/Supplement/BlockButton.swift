//
//  BlockButton.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

class BlockButton: UIButton {
    let borderView = UIView()
    let iconView = UIImageView()
    let textLabel = UILabel()

    override var titleLabel: UILabel? {
        get { nil }
        set { assertionFailure() }
    }

    var actionBlock: () -> Void = {}

    let font = UIFont.systemFont(ofSize: 14, weight: .semibold)
    let spacing: CGFloat = 8
    let inset: CGFloat = 8
    let iconSize: CGFloat = 16

    var strikeThrough: Bool = false {
        didSet { updateStrikes() }
    }

    init(text: String, icon: String) {
        super.init(frame: .zero)

        addSubview(borderView)
        addSubview(iconView)
        addSubview(textLabel)

        iconView.image = UIImage(named: icon)?.withRenderingMode(.alwaysTemplate)
        textLabel.text = text

        applyDefaultAppearance()

        isUserInteractionEnabled = true
        let gesture = UITapGestureRecognizer(target: self, action: #selector(onTapped))
        addGestureRecognizer(gesture)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override var intrinsicContentSize: CGSize {
        .init(
            width: ceil(inset + iconSize + spacing + textLabel.intrinsicContentSize.width + inset),
            height: ceil(max(iconSize, textLabel.intrinsicContentSize.height) + inset * 2),
        )
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        borderView.frame = bounds
        iconView.frame = .init(
            x: inset,
            y: (bounds.height - iconSize) / 2,
            width: iconSize,
            height: iconSize,
        )
        textLabel.frame = .init(
            x: iconView.frame.maxX + spacing,
            y: inset,
            width: bounds.width - iconView.frame.maxX - spacing - inset,
            height: bounds.height - inset * 2,
        )
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }

        applyDefaultAppearance()
        updateAppearanceAfterTraitChange()
    }

    @objc private func onTapped() {
        guard !showsMenuAsPrimaryAction else { return }
        let text = textLabel.text ?? ""
        logger.infoFile("BlockButton tapped: \(text)")
        puddingAnimate()
        actionBlock()
    }

    func applyDefaultAppearance() {
        borderView.backgroundColor = .clear
        borderView.layer.borderColor = UIColor.label.withAlphaComponent(0.1).cgColor
        borderView.layer.borderWidth = 1
        borderView.layer.cornerRadius = 8
        borderView.layer.cornerCurve = .continuous

        iconView.tintColor = .label
        iconView.contentMode = .scaleAspectFit

        textLabel.font = font
        textLabel.textColor = .label
        textLabel.numberOfLines = 1
        textLabel.textAlignment = .center

        updateStrikes()
    }

    func updateStrikes() {
        let baseText = textLabel.text ?? ""
        let attributed = (textLabel.attributedText?.mutableCopy() as? NSMutableAttributedString)
            ?? NSMutableAttributedString(string: baseText)

        attributed.addAttribute(
            .strikethroughStyle,
            value: strikeThrough ? 1 : 0,
            range: NSRange(location: 0, length: attributed.length),
        )

        textLabel.attributedText = attributed
    }

    /// Entry point for subclasses to update UI after trait changes.
    func updateAppearanceAfterTraitChange() {}
}

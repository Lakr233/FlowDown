//
//  VisualInputHintBar.swift
//  FlowDown
//

import UIKit

/// A one-line note under the input box, shown while the draft holds an image
/// that the selected model cannot read.
final class VisualInputHintBar: EditorSectionView {
    let iconView = UIImageView()
    let label = UILabel()

    private let leadingInset: CGFloat = 8
    private let iconSize: CGFloat = 14
    private let iconSpacing: CGFloat = 6
    private let verticalPadding: CGFloat = 2

    private(set) var isActive = false

    override func initializeViews() {
        super.initializeViews()

        iconView.image = UIImage(systemName: "eye.slash")
        iconView.tintColor = .systemOrange
        iconView.contentMode = .scaleAspectFit
        iconView.isAccessibilityElement = false
        addSubview(iconView)

        label.font = .preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.numberOfLines = 0
        addSubview(label)

        alpha = 0
        isHidden = true
        heightPublisher.send(0)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _) in
            self.publishHeight()
        }
    }

    /// Shows or hides the note. Returns true when it just became visible.
    @discardableResult
    func setActive(_ active: Bool, text: String) -> Bool {
        label.text = text
        guard active != isActive else {
            if active { publishHeight() }
            return false
        }
        isActive = active
        isHidden = !active
        doWithAnimation { self.alpha = active ? 1 : 0 }
        publishHeight()
        return active
    }

    private var labelWidth: CGFloat {
        max(0, bounds.width - leadingInset * 2 - iconSize - iconSpacing)
    }

    private func measuredHeight() -> CGFloat {
        guard isActive else { return 0 }
        // Before the first layout the width is unknown; one line is a fair guess.
        let width = labelWidth > 0 ? labelWidth : .greatestFiniteMagnitude
        let size = label.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return ceil(max(size.height, iconSize)) + verticalPadding * 2
    }

    private func publishHeight() {
        heightPublisher.send(measuredHeight())
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard isActive else { return }
        let labelHeight = max(0, bounds.height - verticalPadding * 2)
        label.frame = CGRect(
            x: leadingInset + iconSize + iconSpacing,
            y: verticalPadding,
            width: labelWidth,
            height: labelHeight,
        )
        let firstLineHeight = label.font.lineHeight
        iconView.frame = CGRect(
            x: leadingInset,
            y: verticalPadding + (firstLineHeight - iconSize) / 2,
            width: iconSize,
            height: iconSize,
        )
        // The width is only known now; a wrapped line changes the height.
        publishHeight()
    }
}

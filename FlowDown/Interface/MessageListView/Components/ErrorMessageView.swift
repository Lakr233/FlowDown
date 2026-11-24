//
//  ErrorMessageView.swift
//  FlowDown
//

import UIKit

/// A failed turn in the transcript: the error's description on one red,
/// bold line with a chevron after it, laid out as a summary's title is
/// (`ActivitySummaryView`). Tapping it opens the details in a popover
/// (`ErrorDetailController`); the description is cut at the end to fit.
final class ErrorMessageView: MessageListRowView {
    /// Called with the view the details point at.
    var onOpenDetails: ((UIView) -> Void)?

    private let button = UIControl()
    private let label = UILabel()
    private let chevronView = UIImageView()
    /// Between the description and the chevron.
    static let chevronSpacing: CGFloat = 4

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingTail
        label.textColor = .systemRed
        label.isAccessibilityElement = false
        chevronView.tintColor = .systemRed
        // stays red while the details popover dims the window's tint
        chevronView.tintAdjustmentMode = .normal
        chevronView.contentMode = .center
        chevronView.isAccessibilityElement = false
        button.addSubview(label)
        button.addSubview(chevronView)
        label.isUserInteractionEnabled = false
        chevronView.isUserInteractionEnabled = false
        button.isAccessibilityElement = true
        button.accessibilityTraits = .button
        button.accessibilityHint = String(localized: "View Details")
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            onOpenDetails?(chevronView.isHidden ? label : chevronView)
        }, for: .touchUpInside)
        contentView.addSubview(button)
        themeDidUpdate()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ description: String) {
        // one line: the details hold the rest
        let line = Self.line(of: description)
        label.text = line
        button.accessibilityLabel = line
        setNeedsLayout()
    }

    /// The description on one line, its runs of white space folded into
    /// single spaces.
    static func line(of description: String) -> String {
        description
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func font(from body: UIFont) -> UIFont {
        guard let descriptor = body.fontDescriptor.withSymbolicTraits(.traitBold) else { return body }
        return UIFont(descriptor: descriptor, size: body.pointSize)
    }

    static func height(font body: UIFont) -> CGFloat {
        ActivitySummaryView.headerHeight(font: font(from: body))
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        let font = Self.font(from: theme.fonts.body)
        guard label.font != font else { return }
        label.font = font
        let configuration = UIImage.SymbolConfiguration(
            pointSize: font.pointSize,
            weight: .heavy,
            scale: .small,
        )
        chevronView.image = UIImage(systemName: "chevron.forward", withConfiguration: configuration)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        label.text = nil
        button.accessibilityLabel = nil
        onOpenDetails = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let height = Self.height(font: theme.fonts.body)
        let chevronSize = chevronView.image?.size ?? .zero
        let textRoom = max(0, bounds.width - chevronSize.width - Self.chevronSpacing)
        let textWidth = min(ceil(label.intrinsicContentSize.width), textRoom)
        let width = textWidth + Self.chevronSpacing + chevronSize.width
        let rightToLeft = effectiveUserInterfaceLayoutDirection == .rightToLeft
        // the tap target is the line, not the empty width after it
        button.frame = CGRect(
            x: rightToLeft ? bounds.width - width : 0,
            y: 0,
            width: width,
            height: height,
        )
        let textX = rightToLeft ? width - textWidth : 0
        label.frame = CGRect(x: textX, y: 0, width: textWidth, height: height)
        let chevronX = rightToLeft ? 0 : textWidth + Self.chevronSpacing
        chevronView.frame = CGRect(x: chevronX, y: 0, width: chevronSize.width, height: height)
    }
}

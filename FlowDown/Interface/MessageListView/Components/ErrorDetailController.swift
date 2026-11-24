//
//  ErrorDetailController.swift
//  FlowDown
//

import UIKit

/// A failed turn's whole error, in a small popover pointing at its row
/// (`ErrorMessageView`), with a button that copies it. It stays a popover in
/// compact width too, so it never grows into a sheet.
final class ErrorDetailController: UIViewController, UIPopoverPresentationControllerDelegate {
    let details: String

    private let titleLabel = UILabel()
    private let copyButton = UIButton(configuration: .plain())
    private let textView = UITextView()

    static let width: CGFloat = 300
    static let maximumTextHeight: CGFloat = 220
    static let padding: CGFloat = 16
    static let headerHeight: CGFloat = 30
    static let spacing: CGFloat = 8

    init(details: String, sourceView: UIView) {
        self.details = details
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .popover
        if let popover = popoverPresentationController {
            popover.delegate = self
            popover.sourceView = sourceView
            popover.sourceRect = sourceView.bounds
            popover.permittedArrowDirections = [.up, .down]
        }
        preferredContentSize = Self.contentSize(for: details, width: Self.width)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(details:sourceView:)")
    }

    static var textFont: UIFont {
        UIFont.preferredFont(forTextStyle: .footnote)
    }

    /// As wide as `width`, as tall as the text up to a limit; beyond it the
    /// text scrolls.
    static func contentSize(for details: String, width: CGFloat) -> CGSize {
        let textWidth = width - padding * 2
        let bounding = NSAttributedString(string: details, attributes: [.font: textFont])
            .boundingRect(
                with: CGSize(width: textWidth, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil,
            )
        let textHeight = min(ceil(bounding.height), maximumTextHeight)
        return CGSize(width: width, height: padding + headerHeight + spacing + textHeight + padding)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        titleLabel.text = String(localized: "Error")
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.textColor = .systemRed
        titleLabel.adjustsFontForContentSizeCategory = true
        view.addSubview(titleLabel)

        showCopyButton(copied: false)
        copyButton.addAction(UIAction { [weak self] _ in
            self?.copyDetails()
        }, for: .touchUpInside)
        view.addSubview(copyButton)

        textView.text = details
        textView.font = Self.textFont
        textView.textColor = .label
        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.alwaysBounceVertical = false
        view.addSubview(textView)
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        // inside the popover's safe area, clear of its arrow
        let bounds = view.bounds.inset(by: view.safeAreaInsets)
        let padding = Self.padding
        let width = bounds.width - padding * 2
        let buttonWidth = min(copyButton.sizeThatFits(CGSize(width: width, height: Self.headerHeight)).width, width / 2)
        copyButton.frame = CGRect(
            x: bounds.maxX - padding - buttonWidth + 8,
            y: bounds.minY + padding,
            width: buttonWidth,
            height: Self.headerHeight,
        )
        titleLabel.frame = CGRect(
            x: bounds.minX + padding,
            y: bounds.minY + padding,
            width: max(0, copyButton.frame.minX - bounds.minX - padding - Self.spacing),
            height: Self.headerHeight,
        )
        let textTop = titleLabel.frame.maxY + Self.spacing
        textView.frame = CGRect(
            x: bounds.minX + padding,
            y: textTop,
            width: width,
            height: max(0, bounds.maxY - padding - textTop),
        )
        textView.isScrollEnabled = textView.contentSize.height > textView.bounds.height + 1
    }

    private func showCopyButton(copied: Bool) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = copied ? String(localized: "Copied") : String(localized: "Copy")
        configuration.image = UIImage(systemName: copied ? "checkmark" : "doc.on.doc")
        configuration.preferredSymbolConfigurationForImage = .init(textStyle: .footnote)
        configuration.imagePadding = 4
        configuration.buttonSize = .small
        configuration.contentInsets = .init(top: 4, leading: 8, bottom: 4, trailing: 8)
        configuration.titleTextAttributesTransformer = .init { attributes in
            var attributes = attributes
            attributes.font = .preferredFont(forTextStyle: .subheadline)
            return attributes
        }
        copyButton.configuration = configuration
        view.setNeedsLayout()
    }

    private func copyDetails() {
        UIPasteboard.general.string = details
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        showCopyButton(copied: true)
        UIAccessibility.post(notification: .announcement, argument: String(localized: "Copied"))
    }

    // MARK: - UIPopoverPresentationControllerDelegate

    func adaptivePresentationStyle(for _: UIPresentationController) -> UIModalPresentationStyle {
        .none
    }

    func adaptivePresentationStyle(
        for _: UIPresentationController,
        traitCollection _: UITraitCollection,
    ) -> UIModalPresentationStyle {
        .none
    }
}

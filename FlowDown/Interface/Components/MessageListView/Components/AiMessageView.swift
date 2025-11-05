//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import UIKit

final class AiMessageView: MessageListRowView {
    static let metadataSpacing: CGFloat = 6

    private lazy var modelLabel: UILabel = .init()
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    var modelName: String? {
        didSet {
            let trimmed = modelName?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let trimmed, !trimmed.isEmpty {
                modelLabel.text = trimmed
                modelLabel.isHidden = false
            } else {
                modelLabel.text = nil
                modelLabel.isHidden = true
            }
            setNeedsLayout()
        }
    }

    var linkTapHandler: ((LinkPayload, NSRange, CGPoint) -> Void)? {
        get { markdownView.linkHandler }
        set { markdownView.linkHandler = newValue }
    }

    var codePreviewHandler: ((String?, NSAttributedString) -> Void)? {
        get { markdownView.codePreviewHandler }
        set { markdownView.codePreviewHandler = newValue }
    }

    init() {
        super.init(frame: .zero)
        configureSubviews()
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureSubviews() {
        modelLabel.textColor = .secondaryLabel
        modelLabel.numberOfLines = 0
        modelLabel.isHidden = true
        contentView.addSubview(modelLabel)
        contentView.addSubview(markdownView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        modelName = nil
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        modelLabel.font = theme.fonts.footnote
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        var markdownFrame = contentView.bounds

        if !modelLabel.isHidden {
            let availableWidth = markdownFrame.width
            let size = modelLabel.sizeThatFits(.init(width: availableWidth, height: .greatestFiniteMagnitude))
            let height = ceil(size.height)
            modelLabel.frame = .init(x: 0, y: 0, width: availableWidth, height: height)
            markdownFrame.origin.y += height + Self.metadataSpacing
            markdownFrame.size.height = max(0, markdownFrame.height - height - Self.metadataSpacing)
        } else {
            modelLabel.frame = .zero
        }

        markdownView.frame = markdownFrame
        markdownView.bindContentOffset(from: nearestScrollView)
    }
}

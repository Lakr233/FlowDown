//
//  Created by ktiays on 2025/1/31.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import UIKit

/// The attachments over a user message, against the trailing edge: images in
/// one aspect-aware album, text and audio as cards. Tapping one previews it.
final class UserAttachmentView: MessageListRowView {
    private let attachmentsView = MessageAttachmentsView()
    private var shownID: String?
    /// The Quick Look data source of the preview this row opened, which the
    /// preview controller only holds weakly.
    private var previewDataSource: Any?

    /// The tallest an album or a card is drawn, as the row was measured with.
    var previewHeightLimit: CGFloat = 0 {
        didSet {
            if previewHeightLimit != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// The screen's, as the row was measured with, rather than the row's
    /// own traits, which a row not yet in its window may not have.
    var displayScale: CGFloat = 0 {
        didSet {
            if displayScale != oldValue {
                setNeedsLayout()
            }
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        attachmentsView.onPreview = { [weak self] item in
            guard let self else { return }
            previewDataSource = AttachmentsBar.presentReadOnlyPreview(for: item, from: self)
        }
        contentView.addSubview(attachmentsView)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        shownID = nil
        attachmentsView.show([], animated: false)
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let bounds = contentView.bounds
        let width = UserMessageView.availableContentWidth(for: bounds.width)
        attachmentsView.previewHeightLimit = previewHeightLimit
        attachmentsView.displayScale = displayScale
        attachmentsView.frame = contentView.directionalFrame(CGRect(
            x: bounds.width - width,
            y: 0,
            width: width,
            height: bounds.height,
        ))
    }

    func update(with attachments: MessageListView.Attachments) {
        let isSameMessage = shownID == attachments.id
        shownID = attachments.id
        attachmentsView.show(attachments.items, animated: isSameMessage)
        setNeedsLayout()
    }

    static func height(
        for attachments: MessageListView.Attachments,
        containerWidth: CGFloat,
        previewHeightLimit: CGFloat,
        displayScale: CGFloat,
    ) -> CGFloat {
        MessageAttachmentsView.height(
            for: attachments.items,
            width: UserMessageView.availableContentWidth(for: containerWidth),
            maximumPreviewHeight: previewHeightLimit,
            displayScale: displayScale,
        )
    }
}

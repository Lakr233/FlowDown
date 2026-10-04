//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import Storage
import UIKit

final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownStreamView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    private var representedMessageID: Message.ID?
    private var representedPackage: MarkdownContent?

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
        contentView.addSubview(markdownView)
    }

    /// Puts the message content on screen. The first fill for a message is
    /// applied synchronously so a new row never renders blank; subsequent
    /// updates to the same message go through the stream view, which fades
    /// new text in while `isStreaming` and throttles otherwise.
    ///
    /// The list keeps this row for its message, so mounting it again hands
    /// back the content it already shows; that is skipped rather than rebuilt.
    func setMarkdownPackage(_ package: MarkdownContent, for messageID: Message.ID, isStreaming: Bool) {
        markdownView.streamIdentity = messageID
        markdownView.isStreaming = isStreaming
        guard package !== representedPackage else { return }
        representedPackage = package
        if representedMessageID == messageID {
            markdownView.setContent(package)
        } else {
            representedMessageID = messageID
            markdownView.setContentImmediately(package)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markdownView.frame = contentView.bounds
        markdownView.trackedScrollView = nearestScrollView
    }
}

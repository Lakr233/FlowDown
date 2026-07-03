//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import UIKit

final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        $0.throttleInterval = 1 / 60
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
        contentView.addSubview(markdownView)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Parked cells still receive CodeHighlighter notifications which trigger
        // a full document rebuild; empty their content so that rebuild is free.
        markdownView.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markdownView.frame = contentView.bounds
        markdownView.trackedScrollView = nearestScrollView
    }
}

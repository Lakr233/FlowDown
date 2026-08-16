//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import Storage
import UIKit

final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: MarkdownTextView = .init().with {
        // Assistant updates are coalesced by this row's display link. Keeping
        // MarkdownView immediate gives every rebuild a known, nonzero width.
        $0.throttleInterval = nil
    }

    private var representedMessageID: Message.ID?
    private var pendingPackage: MarkdownContent?
    private var displayLink: CADisplayLink?

    var codeExpandedBlocks: Set<Int> = [] {
        didSet { markdownView.expandedCodeBlocks = codeExpandedBlocks }
    }
    var codeBlockExpansionHandler: ((_ blockIndex: Int, _ isExpanded: Bool) -> Void)?

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

    deinit {
        displayLink?.invalidate()
    }

    private func configureSubviews() {
        markdownView.codeBlockExpansionDidChange = { [weak self] blockIndex, isExpanded in
            self?.codeBlockExpansionHandler?(blockIndex, isExpanded)
        }
        contentView.addSubview(markdownView)
    }

    /// Builds a fenced-code view only after this row has a usable width.
    /// Streaming packages are coalesced to the display cadence so a code view
    /// is never torn down and rebuilt several times in one rendered frame.
    func setMarkdownPackage(_ package: MarkdownContent, for messageID: Message.ID) {
        let isNewMessage = representedMessageID != messageID
        representedMessageID = messageID
        pendingPackage = package

        if isNewMessage {
            displayLink?.invalidate()
            displayLink = nil
            setNeedsLayout()
            layoutIfNeeded()
            flushPendingPackageIfPossible()
        } else {
            schedulePendingPackage()
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        displayLink?.invalidate()
        displayLink = nil
        pendingPackage = nil
        representedMessageID = nil
        codeExpandedBlocks = []
        codeBlockExpansionHandler = nil
        // Parked cells still receive CodeHighlighter notifications which trigger
        // a full document rebuild; empty their content so that rebuild is free.
        markdownView.reset()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markdownView.frame = contentView.bounds
        markdownView.trackedScrollView = nearestScrollView

        // Initial conversation loads configure a row before its first visible
        // layout. There is no display link yet, so finish that package here.
        if displayLink == nil {
            flushPendingPackageIfPossible()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        // A conversation opened for the first time installs its rows while the
        // hierarchy is not attached to a window yet. Force one real layout pass
        // once it is, so fenced-code views placed against the detached tree are
        // re-synced instead of waiting for a window resize.
        guard window != nil else { return }
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func schedulePendingPackage() {
        guard pendingPackage != nil else { return }
        guard window != nil else {
            setNeedsLayout()
            return
        }
        guard displayLink == nil else { return }

        let displayLink = CADisplayLink(target: self, selector: #selector(flushPendingPackageOnDisplayLink))
        displayLink.add(to: .main, forMode: .common)
        self.displayLink = displayLink
    }

    @objc private func flushPendingPackageOnDisplayLink() {
        flushPendingPackageIfPossible()
        guard pendingPackage == nil else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    private func flushPendingPackageIfPossible() {
        guard let package = pendingPackage, contentView.bounds.width > 0 else { return }
        pendingPackage = nil

        UIView.performWithoutAnimation {
            self.markdownView.frame = self.contentView.bounds
            self.markdownView.trackedScrollView = self.nearestScrollView
            self.markdownView.setContentImmediately(package)
            self.markdownView.textLabelView.preferredMaxLayoutWidth = self.contentView.bounds.width
            self.markdownView.textLabelView.reloadTextLayout()
            self.markdownView.setNeedsLayout()
            self.markdownView.layoutIfNeeded()
        }
    }
}

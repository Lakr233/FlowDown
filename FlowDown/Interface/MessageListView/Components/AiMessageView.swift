//
//  Created by ktiays on 2025/2/6.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import MarkdownView
import Storage
import UIKit

/// The agent's reply, drawn by `ChatMarkdownView`: new text fades in while
/// it streams, and the last chunk finishes fading before streaming ends.
final class AiMessageView: MessageListRowView {
    private(set) lazy var markdownView: ChatMarkdownView = .init().with {
        $0.throttleInterval = 1 / 60
    }

    private var representedMessageID: Message.ID?
    private var representedPackage: MarkdownContent?
    /// The content the view shows in full right now: what was last put in
    /// it at once. Nil while an update is on its way through the stream
    /// view, which shows it a moment later.
    private var settledPackage: MarkdownContent?
    /// The width the reply was last typeset at for ``contentHeight(showing:width:)``,
    /// while it still shows what it showed then.
    private(set) var typesetWidth: CGFloat?
    /// The reply has finished, but its last text is still fading in.
    private var finishesStreamWhenStill = false
    private var revealObservation: NSKeyValueObservation?

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
        contentView.addSubview(markdownView)
        revealObservation = markdownView.streamLabel.observe(\.isAnimating) { [weak self] _, _ in
            // Called while the label is still taking its animation down.
            DispatchQueue.main.async { [weak self] in
                guard let self, finishesStreamWhenStill, !markdownView.streamLabel.isAnimating else { return }
                finishStream()
            }
        }
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Puts the message content on screen. The first fill for a message is
    /// applied synchronously so a new row never renders blank; subsequent
    /// updates to the same message go through the stream view, which fades
    /// new text in while `isStreaming` and throttles otherwise.
    ///
    /// The list keeps this row for its message, so mounting it again hands
    /// back the content it already shows; that is skipped rather than rebuilt.
    func setMarkdownPackage(_ package: MarkdownContent, for messageID: Message.ID, isStreaming: Bool) {
        let firstFill = representedMessageID != messageID
        markdownView.streamIdentity = messageID
        let animates = !UIAccessibility.isReduceMotionEnabled
        // The update that ends a reply often brings its last chunk too.
        // Turning streaming off now would show that chunk and the text
        // still fading at once, so it stays on until the label is still.
        if !isStreaming, animates, !firstFill, markdownView.isStreaming {
            finishesStreamWhenStill = true
        } else {
            finishesStreamWhenStill = false
            markdownView.isStreaming = isStreaming && animates
        }
        if package !== representedPackage {
            representedPackage = package
            typesetWidth = nil
            if firstFill {
                representedMessageID = messageID
                markdownView.setContentImmediately(package)
                settledPackage = package
            } else {
                markdownView.setContent(package)
                settledPackage = nil
            }
        }
        if finishesStreamWhenStill, !markdownView.streamLabel.isAnimating {
            finishStream()
        }
    }

    /// Has a reply drawn in tiles bring them to where the list just put it, in
    /// the frame that shows it there.
    ///
    /// A label keeps tiles around the part of it on screen and finds that part
    /// itself when a scroll view scrolls. A list also moves a row without
    /// scrolling: measuring the rows above it shifts every row below, by more
    /// than a screen after a resize. The label looks in its own layout pass, so
    /// asking for one here, while the list is laying out, makes its tiles in
    /// the same frame. A reply that is not tiled is left alone.
    func updateTilesAfterListLayout() {
        let label = markdownView.textLabelView
        guard let tiles = label.tiledDrawing, label.bounds.height > tiles.threshold else { return }
        label.setNeedsLayout()
    }

    /// The height of the reply at `width`, measured on the view that draws
    /// it, or nil unless that view shows exactly `package`: a reply still
    /// streaming, or one whose update has yet to reach the view, would be
    /// measured as it was.
    func contentHeight(showing package: MarkdownContent, width: CGFloat) -> CGFloat? {
        guard settledPackage === package, !markdownView.isStreaming, !finishesStreamWhenStill else { return nil }
        typesetWidth = width
        return markdownView.boundingSize(for: width).height
    }

    private func finishStream() {
        finishesStreamWhenStill = false
        markdownView.isStreaming = false
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        markdownView.frame = contentView.bounds
        markdownView.trackedScrollView = nearestScrollView
    }
}

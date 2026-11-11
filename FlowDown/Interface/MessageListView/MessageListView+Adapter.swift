//
//  Created by ktiays on 2025/1/29.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import AlertController
import ListViewKit
import Litext
import MarkdownView
import Storage
import UIKit

extension MessageListView {
    /// Declares the row types the list can display. Registrations are matched
    /// in declaration order, so each one narrows itself to a single entry case.
    func registerRows() {
        listView.rows {
            ListRow(UserMessageView.self)
                .when { if case .userContent = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .userContent(_, message, attachments) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { containerWidth in
                        UserMessageView.height(
                            for: message,
                            attachments: attachments,
                            containerWidth: containerWidth,
                            theme: self.theme,
                            attachmentHeightLimit: self.attachmentPreviewHeightLimit,
                            displayScale: self.attachmentDisplayScale,
                        )
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .userContent(_, message, attachments) = entry else { return }
                    prepare(row, for: entry)
                    row.attachmentHeightLimit = attachmentPreviewHeightLimit
                    row.displayScale = attachmentDisplayScale
                    row.show(message, attachments: attachments)
                }

            ListRow(ActivitySummaryView.self)
                .when { if case .activity = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .activity(summary) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { containerWidth in
                        ActivitySummaryView.height(
                            for: summary,
                            font: self.theme.fonts.body,
                            stepFont: self.theme.fonts.footnote,
                            width: containerWidth,
                        )
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .activity(summary) = entry else { return }
                    prepare(row, for: entry)
                    row.show(summary)
                    row.onOpenTrace = { [weak self] in
                        self?.presentTrace(for: summary.id)
                    }
                }

            ListRow(AiMessageView.self)
                .when { if case .aiContent = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .aiContent(_, message) = entry else { return 0 }
                    return aiRowHeight(for: message, inListWidth: context.width)
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .aiContent(messageID, message) = entry else { return }
                    prepare(row, for: entry)
                    let package = markdownPackageCache.package(for: message, theme: theme)
                    row.setMarkdownPackage(package, for: messageID, isStreaming: message.isStreaming)
                    row.linkTapHandler = { [weak self, weak row] link, range, touchLocation in
                        guard let self, let row else { return }
                        handleLinkTapped(link, in: range, at: row.convert(touchLocation, to: self))
                    }
                    row.codePreviewHandler = { [weak self] lang, code in
                        self?.presentAndReturnDetailCodeController(
                            code: code,
                            language: lang,
                            title: String(localized: "Code Viewer"),
                        )
                    }
                }

            ListRow(HintMessageView.self)
                .when { if case .hint = $0 { true } else { false } }
                .height { [weak self] _, context in
                    guard let self else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in
                        ceil(self.theme.fonts.footnote.lineHeight + 16)
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .hint(_, content) = entry else { return }
                    prepare(row, for: entry)
                    row.text = content
                }

            ListRow(ActivityReportingView.self)
                .when { if case .activityReporting = $0 { true } else { false } }
                .height { [weak self] _, context in
                    guard let self else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in
                        ActivityReportingView.height(font: self.theme.fonts.body)
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .activityReporting(content) = entry else { return }
                    prepare(row, for: entry)
                    row.text = content
                }
        }
    }

    /// The height of an AI message row, measured on a pooled sizing view. The
    /// row registration and the off-screen preparation both read it, so a row
    /// prepared ahead of time is mounted at exactly the height it was laid out at.
    func aiRowHeight(for message: MessageRepresentation, inListWidth listWidth: CGFloat) -> CGFloat {
        rowHeight(inListWidth: listWidth) { containerWidth in
            let sizingView = markdownSizingViewPool.view(for: message, theme: theme) {
                markdownPackageCache.package(for: message, theme: theme)
            }
            return ceil(sizingView.boundingSize(for: containerWidth).height)
        }
    }

    /// Wraps a content height in the shared row insets, mirroring the layout
    /// `MessageListRowView` performs. Returns zero while the list has no width
    /// to lay out in.
    private func rowHeight(inListWidth listWidth: CGFloat, content: (CGFloat) -> CGFloat) -> CGFloat {
        let listRowInsets = MessageListView.listRowInsets(for: listWidth)
        let containerWidth = max(0, listWidth - listRowInsets.horizontal)
        guard containerWidth > 0 else { return 0 }
        return content(containerWidth) + listRowInsets.bottom
    }

    /// The tallest an attachment album or card is drawn: 30% of the screen,
    /// which holds still while the window resizes, so a row is always laid
    /// out at the height it was measured at.
    private var attachmentPreviewHeightLimit: CGFloat {
        let screenHeight = window?.windowScene?.screen.bounds.height ?? 800
        return max(120, (screenHeight * 0.3).rounded())
    }

    /// The screen's scale, which makes an image's pixels its own size in points.
    private var attachmentDisplayScale: CGFloat {
        window?.windowScene?.screen.scale ?? traitCollection.displayScale
    }

    /// Applies the state every row shares: the current theme, and a context
    /// menu bound to the concrete row view so menu actions (eg. Copy as Image)
    /// can render it without querying snapshots or indexes.
    private func prepare(_ rowView: MessageListRowView, for entry: Entry) {
        rowView.theme = theme
        rowView.contextMenuProvider = { [weak self, weak rowView] pointInRowContentView in
            guard let self, let rowView else { return nil }
            let pointInListView = listView.convert(pointInRowContentView, from: rowView.contentView)
            guard !hasActivatedEventOnLabel(location: pointInListView) else { return nil }
            return contextMenu(for: entry, referenceView: rowView)
        }
    }

    private func hasActivatedEventOnLabel(location: CGPoint) -> Bool {
        var lookup: [UIView] = listView.subviews
        while !lookup.isEmpty {
            let view = lookup.removeFirst()
            lookup.append(contentsOf: view.subviews)
            if let label = view as? TextLabelView {
                if label.selectionRange != nil {
                    if label.selectionContains(location, from: listView) {
                        Logger.ui.debugFile("event is activate on \(label)")
                        return true
                    }
                    label.clearSelection()
                }
            }
        }
        Logger.ui.debugFile("no event, returning false")
        return false
    }

    private func contextMenu(for entry: Entry, referenceView: UIView?) -> UIMenu? {
        let messageIdentifier: Message.ID
        let representation: MessageRepresentation

        switch entry {
        case let .userContent(msgID, messageRepresentation, _):
            messageIdentifier = msgID
            representation = messageRepresentation
        case let .aiContent(msgID, messageRepresentation):
            messageIdentifier = msgID
            representation = messageRepresentation
        default:
            return nil
        }

        return buildMenu(
            for: messageIdentifier,
            representation: representation,
            referenceView: referenceView,
        )
    }

    /// Opens the trace behind a summary in a sheet, which follows the run
    /// while it stays open (`updateOpenTrace`).
    private func presentTrace(for summaryID: String) {
        guard let summary = currentSummary(withID: summaryID) else { return }
        let controller = TraceController(summary: summary) { [weak self] messageID in
            guard let self, let message = session.message(for: messageID) else { return nil }
            return session.decodeToolRequestFromToolMessage(message)?.args
        }
        openTrace = controller
        presentSheet(controller)
    }

    private func currentSummary(withID id: String) -> ActivitySummary? {
        for entry in entries {
            if case let .activity(summary) = entry, summary.id == id {
                return summary
            }
        }
        return nil
    }

    /// Shows the open trace's summary as the list now has it.
    func updateOpenTrace() {
        guard let openTrace, let summary = currentSummary(withID: openTrace.summaryID) else { return }
        openTrace.show(summary)
    }

    private func presentSheet(_ controller: UIViewController) {
        #if targetEnvironment(macCatalyst)
            let nav = UINavigationController(rootViewController: controller)
            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                primaryAction: UIAction { [weak nav] _ in nav?.dismiss(animated: true) },
            )
            controller.navigationItem.leftBarButtonItem?.accessibilityLabel = String(localized: "Close")
            let holder = AlertBaseController(
                rootViewController: nav,
                preferredWidth: 555,
                preferredHeight: 555,
            )
            holder.shouldDismissWhenTappedAround = true
            holder.shouldDismissWhenEscapeKeyPressed = true
        #else
            let holder = FadeBarNavigationController(rootViewController: controller)
            controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "xmark"),
                primaryAction: UIAction { [weak holder] _ in holder?.dismiss(animated: true) },
            )
            controller.navigationItem.leftBarButtonItem?.accessibilityLabel = String(localized: "Close")
            holder.modalPresentationStyle = .formSheet
        #endif
        parentViewController?.present(holder, animated: true)
    }

    private func buildMenu(
        for messageIdentifier: Message.ID,
        representation: MessageRepresentation,
        referenceView: UIView?,
    ) -> UIMenu {
        UIMenu(children: [
            UIMenu(options: [.displayInline], children: [
                { () -> UIAction? in
                    guard let message = session.message(for: messageIdentifier),
                          message.role == .user,
                          session.nearestUserMessage(beforeOrEqual: messageIdentifier) != nil
                    else { return nil }
                    return UIAction(title: String(localized: "Retry"), image: .init(systemName: "arrow.clockwise")) { [weak self] _ in
                        guard let self else { return }
                        session.retry(byClearAfter: messageIdentifier)
                    }
                }(),
                { () -> UIAction? in
                    guard let message = session.message(for: messageIdentifier),
                          message.role == .user
                    else { return nil }
                    guard let editor = self.nearestEditor() else { return nil }
                    return UIAction(title: String(localized: "Redo (Edit)"), image: .init(systemName: "arrow.clockwise")) { _ in
                        let attachments: [RichEditorView.Object.Attachment] = self.session
                            .attachments(for: messageIdentifier)
                            .compactMap {
                                guard let type: RichEditorView.Object.Attachment.AttachmentType = .init(rawValue: $0.type) else {
                                    return nil
                                }
                                return RichEditorView.Object.Attachment(
                                    id: .init(),
                                    type: type,
                                    name: $0.name,
                                    previewImage: $0.previewImageData,
                                    imageRepresentation: $0.imageRepresentation,
                                    textRepresentation: $0.representedDocument,
                                    storageSuffix: $0.storageSuffix,
                                )
                            }
                        editor.refill(withText: message.document, attachments: attachments)
                        self.session.deleteCurrentAndAfter(messageIdentifier: messageIdentifier)
                        Task { @MainActor in
                            editor.focus()
                        }
                    }
                }(),
                { () -> UIAction? in
                    guard let message = session.message(for: messageIdentifier),
                          message.role == .assistant,
                          session.nearestUserMessage(beforeOrEqual: messageIdentifier) != nil
                    else { return nil }
                    return UIAction(title: String(localized: "Retry"), image: .init(systemName: "arrow.clockwise")) { [weak self] _ in
                        guard let self else { return }
                        session.retry(byClearAfter: messageIdentifier)
                    }
                }(),
            ].compactMap(\.self)),
            UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Copy"), image: .init(systemName: "doc.on.doc")) { _ in
                    UIPasteboard.general.string = representation.content
                    Indicator.present(
                        title: "Copied",
                        preset: .done,
                        referencingView: self,
                    )
                },
                UIAction(title: String(localized: "View Raw"), image: .init(systemName: "eye")) { [weak self] _ in
                    self?.presentAndReturnDetailCodeController(
                        code: .init(string: representation.content),
                        language: "markdown",
                        title: String(localized: "Raw Content"),
                    )
                },
            ].compactMap(\.self)),
            UIMenu(title: String(localized: "Rewrite"), image: .init(systemName: "arrow.uturn.left"), options: [], children: [
                RewriteAction.allCases.map { action in
                    UIAction(title: action.title, image: action.icon) { [weak self] _ in
                        guard let self else { return }
                        action.send(to: session, message: messageIdentifier, bindView: self)
                    }
                },
            ].flatMap(\.self).compactMap(\.self)),
            UIMenu(title: String(localized: "More"), image: .init(systemName: "ellipsis.circle"), children: [
                UIMenu(title: String(localized: "More"), options: [.displayInline], children: [
                    UIAction(title: String(localized: "Copy as Image"), image: .init(systemName: "text.below.photo")) { [weak self] _ in
                        guard let self else { return }
                        guard let rowView = referenceView else { return }
                        let render = UIGraphicsImageRenderer(bounds: rowView.bounds)
                        let image = render.image { ctx in
                            rowView.layer.render(in: ctx.cgContext)
                        }
                        UIPasteboard.general.image = image
                        Indicator.present(
                            title: "Copied",
                            preset: .done,
                            referencingView: self,
                        )
                    },
                ]),
                UIMenu(options: [.displayInline], children: [
                    UIAction(title: String(localized: "Edit"), image: .init(systemName: "pencil")) { [weak self] _ in
                        let viewer = self?.presentAndReturnDetailCodeController(
                            code: .init(string: representation.content),
                            language: "markdown",
                            title: String(localized: "Edit"),
                        )
                        guard let viewer = viewer as? CodeEditorController else {
                            assertionFailure()
                            return
                        }
                        viewer.collectEditedContent { [weak self] text in
                            guard let self else { return }
                            Logger.ui.infoFile("edited \(messageIdentifier) content: \(text)")
                            session?.update(messageIdentifier: messageIdentifier, content: text)
                        }
                    },
                    UIAction(title: String(localized: "Share"), image: .init(systemName: "doc.on.doc")) { [weak self] _ in
                        guard let self else { return }
                        DisposableExporter(data: Data(representation.content.utf8), pathExtension: "txt")
                            .run(anchor: referenceView ?? self, mode: .text)
                    },
                ]),
                UIMenu(options: [.displayInline], children: [
                    UIAction(title: String(localized: "Delete"), image: .init(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        self?.session.delete(messageIdentifier: messageIdentifier)
                    },
                    UIAction(title: String(localized: "Delete w/ After"), image: .init(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        self?.session?.deleteCurrentAndAfter(messageIdentifier: messageIdentifier)
                    },
                ]),
            ]),
        ])
    }

    @discardableResult
    func presentAndReturnDetailCodeController(
        code: NSAttributedString,
        language: String?,
        title: String
    ) -> UIViewController {
        let controller: UIViewController

        if language?.lowercased() == "html" {
            controller = HTMLPreviewController(content: code.string)
        } else {
            controller = CodeEditorController(language: language, text: code.string)
            controller.title = title
        }

        #if targetEnvironment(macCatalyst)
            let nav = UINavigationController(rootViewController: controller)
            nav.view.backgroundColor = .background
            let holder = AlertBaseController(
                rootViewController: nav,
                preferredWidth: 555,
                preferredHeight: 555,
            )
            holder.shouldDismissWhenTappedAround = true
            holder.shouldDismissWhenEscapeKeyPressed = true
        #else
            let holder = FadeBarNavigationController(rootViewController: controller)
            holder.preferredContentSize = .init(width: 555, height: 555 - holder.navigationBar.frame.height)
            holder.modalTransitionStyle = .coverVertical
            holder.modalPresentationStyle = .formSheet
            holder.view.backgroundColor = .background
        #endif
        parentViewController?.present(holder, animated: true)
        return controller
    }
}

private extension UIView {
    func nearestEditor() -> RichEditorView? {
        var views = window?.subviews ?? []
        var index = 0
        repeat {
            let view = views[index]
            if let editor = view as? RichEditorView {
                return editor
            }
            views.append(contentsOf: view.subviews)
            index += 1
        } while index < views.count
        return nil
    }
}

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
                    guard let self, case let .userContent(_, message) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { containerWidth in
                        let attributedContent = NSAttributedString(string: message.content, attributes: [
                            .font: self.theme.fonts.body,
                        ])
                        let availableWidth = UserMessageView.availableTextWidth(for: containerWidth)
                        return self.boundingSize(with: availableWidth, for: attributedContent).height
                            + UserMessageView.textPadding * 2
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .userContent(_, message) = entry else { return }
                    prepare(row, for: entry)
                    row.text = message.content
                }

            ListRow(UserAttachmentView.self)
                .when { if case .userAttachment = $0 { true } else { false } }
                .height { [weak self] _, context in
                    guard let self else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in AttachmentsBar.itemHeight }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .userAttachment(_, attachments) = entry else { return }
                    prepare(row, for: entry)
                    row.update(with: attachments)
                }

            ListRow(ReasoningContentView.self)
                .when { if case .reasoningContent = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .reasoningContent(_, message) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { containerWidth in
                        guard message.isRevealed else { return ReasoningContentView.unrevealedTileHeight }
                        let attributedContent = NSAttributedString(string: message.content, attributes: [
                            .font: self.theme.fonts.footnote,
                            .paragraphStyle: ReasoningContentView.paragraphStyle,
                        ])
                        return self.boundingSize(with: containerWidth - 16, for: attributedContent).height
                            + ReasoningContentView.spacing + ReasoningContentView.revealedTileHeight + 2
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .reasoningContent(_, message) = entry else { return }
                    prepare(row, for: entry)
                    row.isRevealed = message.isRevealed
                    row.isThinking = message.isThinking
                    row.thinkingDuration = message.thinkingDuration
                    row.text = message.content
                    row.thinkingTileTapHandler = { [weak self] newValue in
                        guard let self else { return }
                        let thinkingMessages = session.messages.filter {
                            $0.combinationID == message.id
                        }
                        guard let thinkingMessage = thinkingMessages.first else {
                            return
                        }
                        thinkingMessage.update(\.isThinkingFold, to: !newValue)
                        updateList(animated: true)
                        session.save()
                    }
                }

            ListRow(AiMessageView.self)
                .when { if case .aiContent = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .aiContent(_, message) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { containerWidth in
                        let sizingView = self.markdownSizingViewPool.view(for: message, theme: self.theme) {
                            self.markdownPackageCache.package(for: message, theme: self.theme)
                        }
                        return ceil(sizingView.boundingSize(for: containerWidth).height)
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .aiContent(messageID, message) = entry else { return }
                    prepare(row, for: entry)
                    let package = markdownPackageCache.package(for: message, theme: theme)
                    row.setMarkdownPackage(package, for: messageID)
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

            ListRow(WebSearchStateView.self)
                .when { if case .webSearchContent = $0 { true } else { false } }
                .height { [weak self] _, context in
                    guard let self else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in
                        WebSearchStateView.intrinsicHeight(withLabelFont: self.theme.fonts.body)
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .webSearchContent(webSearchPhase) = entry else { return }
                    prepare(row, for: entry)
                    row.update(with: webSearchPhase)
                }

            ListRow(ActivityReportingView.self)
                .when { if case .activityReporting = $0 { true } else { false } }
                .height { [weak self] entry, context in
                    guard let self, case let .activityReporting(content) = entry else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in
                        let contentHeight = self.boundingSize(with: .infinity, for: .init(string: content, attributes: [
                            .font: self.theme.fonts.body,
                        ])).height
                        return max(contentHeight, ActivityReportingView.loadingSymbolSize.height + 16)
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .activityReporting(content) = entry else { return }
                    prepare(row, for: entry)
                    row.text = content
                }

            ListRow(ToolHintView.self)
                .when { if case .toolCallStatus = $0 { true } else { false } }
                .height { [weak self] _, context in
                    guard let self else { return 0 }
                    return rowHeight(inListWidth: context.width) { _ in
                        self.theme.fonts.body.lineHeight + 20
                    }
                }
                .configure { [weak self] row, entry, _ in
                    guard let self, case let .toolCallStatus(messageID, status) = entry else { return }
                    prepare(row, for: entry)
                    row.toolName = status.name
                    row.text = status.message
                    row.state = switch status.state {
                    case 0: .running
                    case 1: .suceeded
                    default: .failed
                    }
                    row.clickHandler = { [weak self] in
                        self?.presentToolCallDetails(for: messageID, status: status)
                    }
                }
        }
    }

    /// Wraps a content height in the shared row insets, mirroring the layout
    /// `MessageListRowView` performs. Returns zero while the list has no width
    /// to lay out in.
    private func rowHeight(inListWidth listWidth: CGFloat, content: (CGFloat) -> CGFloat) -> CGFloat {
        let listRowInsets = MessageListView.listRowInsets
        let containerWidth = max(0, listWidth - listRowInsets.horizontal)
        guard containerWidth > 0 else { return 0 }
        return content(containerWidth) + listRowInsets.bottom
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

    private func boundingSize(with width: CGFloat, for attributedString: NSAttributedString) -> CGSize {
        labelForSizeCalculation.preferredMaxLayoutWidth = width
        labelForSizeCalculation.attributedText = attributedString
        let contentSize = labelForSizeCalculation.intrinsicContentSize
        return .init(width: ceil(contentSize.width), height: ceil(contentSize.height))
    }

    private func hasActivatedEventOnLabel(location: CGPoint) -> Bool {
        var lookup: [UIView] = listView.subviews
        while !lookup.isEmpty {
            let view = lookup.removeFirst()
            lookup.append(contentsOf: view.subviews)
            if let label = view as? TextLabelView {
                if label.selectionRange != nil {
                    let location = label.convert(location, from: listView)
                    if label.selectionContains(location) {
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
        let isReasoningContent: Bool

        switch entry {
        case let .userContent(msgID, messageRepresentation):
            messageIdentifier = msgID
            representation = messageRepresentation
            isReasoningContent = false
        case let .reasoningContent(msgID, messageRepresentation):
            messageIdentifier = msgID
            representation = messageRepresentation
            isReasoningContent = true
        case let .aiContent(msgID, messageRepresentation):
            messageIdentifier = msgID
            representation = messageRepresentation
            isReasoningContent = false
        case let .toolCallStatus(messageID, status):
            let action = UIAction(
                title: String(localized: "View Details"),
                image: UIImage(systemName: "doc.text.magnifyingglass"),
            ) { [weak self] _ in
                self?.presentToolCallDetails(for: messageID, status: status)
            }
            return UIMenu(children: [action])
        default:
            return nil
        }

        return buildMenu(
            for: messageIdentifier,
            representation: representation,
            isReasoningContent: isReasoningContent,
            referenceView: referenceView,
        )
    }

    private func presentToolCallDetails(for messageIdentifier: Message.ID, status: Message.ToolStatus) {
        let text = NSAttributedString(string: toolCallDetailsText(for: messageIdentifier, status: status))
        presentAndReturnDetailCodeController(
            code: text,
            language: "json",
            title: String(localized: "Text Content"),
        )
    }

    private func toolCallDetailsText(for messageIdentifier: Message.ID, status: Message.ToolStatus) -> String {
        var sections: [String] = []

        let title = switch status.state {
        case 1:
            String(localized: "Tool call for \(status.name) completed.")
        case 2:
            String(localized: "Tool call for \(status.name) failed.")
        default:
            String(localized: "Tool call for \(status.name) running")
        }
        sections.append(title)

        if let message = session.message(for: messageIdentifier) {
            if let toolRequest = session.decodeToolRequestFromToolMessage(message) {
                var parameterText = toolRequest.args
                if let pretty = prettyPrintedJSON(from: toolRequest.args) {
                    parameterText = pretty
                }
                sections.append([
                    String(localized: "Parameters"),
                    parameterText,
                ].joined(separator: "\n\n"))
            } else {
                sections.append(String(localized: "Unable to decode tool parameters."))
            }
        } else {
            sections.append(String(localized: "Unable to locate the tool message in this session."))
        }

        let trimmedResult = status.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedResult.isEmpty {
            var formattedResult = trimmedResult
            if let pretty = prettyPrintedJSON(from: trimmedResult) {
                formattedResult = pretty
            }
            sections.append([
                String(localized: "Result"),
                formattedResult,
            ].joined(separator: "\n\n"))
        }

        return sections.joined(separator: "\n\n")
    }

    private func prettyPrintedJSON(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    private func buildMenu(
        for messageIdentifier: Message.ID,
        representation: MessageRepresentation,
        isReasoningContent: Bool,
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
                        session.retry(byClearAfter: messageIdentifier, currentMessageListView: self)
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
                        session.retry(byClearAfter: messageIdentifier, currentMessageListView: self)
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
                            if isReasoningContent {
                                session?.update(messageIdentifier: messageIdentifier, reasoningContent: text)
                            } else {
                                session?.update(messageIdentifier: messageIdentifier, content: text)
                            }
                        }
                    },
                    UIAction(title: String(localized: "Share"), image: .init(systemName: "doc.on.doc")) { [weak self] _ in
                        guard let self else { return }
                        DisposableExporter(data: Data(representation.content.utf8), pathExtension: "txt")
                            .run(anchor: self, mode: .text)
                    },
                ]),
                UIMenu(options: [.displayInline], children: [
                    UIAction(title: String(localized: "Delete"), image: .init(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        if isReasoningContent {
                            self?.session.update(messageIdentifier: messageIdentifier, reasoningContent: "")
                        } else {
                            self?.session.delete(messageIdentifier: messageIdentifier)
                        }
                    },
                    UIAction(title: String(localized: "Delete w/ After"), image: .init(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                        self?.session?.deleteCurrentAndAfter(messageIdentifier: messageIdentifier)
                    },
                ]),
            ]),
        ])
    }

    @discardableResult
    func presentAndReturnDetailCodeController(code: NSAttributedString, language: String?, title: String) -> UIViewController {
        let controller: UIViewController

        if language?.lowercased() == "html" {
            controller = HTMLPreviewController(content: code.string)
        } else {
            controller = CodeEditorController(language: language, text: code.string)
            controller.title = title
        }

        let size = ModalWindowSize.resolve(in: parentViewController?.view.window)
        #if targetEnvironment(macCatalyst)
            let nav = UINavigationController(rootViewController: controller)
            nav.view.backgroundColor = .background
            let holder = AlertBaseController(
                rootViewController: nav,
                preferredWidth: size.width,
                preferredHeight: size.height,
            )
            holder.shouldDismissWhenTappedAround = true
            holder.shouldDismissWhenEscapeKeyPressed = true
        #else
            let holder = UINavigationController(rootViewController: controller)
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

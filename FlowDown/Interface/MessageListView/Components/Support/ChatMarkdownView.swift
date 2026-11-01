import Litext
import LitextAnimation
import MarkdownView
import SwiftUI
import Translation
import UIKit

/// Ordinary blocks share a gap; list items keep their own compact spacing.
final class ChatMarkdownView: MarkdownStreamView {
    static let blockSpacing: CGFloat = 16

    /// Whether the label reads the document shown now (`updateSpokenText`).
    private var spokenTextIsCurrent = false

    /// How long every streamed character takes to fade in, so even a chunk of
    /// one character takes this long to appear in full.
    static let revealDuration: TimeInterval = 0.5

    /// The worker coalesces streamed text to 250 ms, so a chunk sweeps in over
    /// about that long. A chunk arriving mid-sweep starts behind the one before
    /// and shortens its own sweep to end within 0.25 s of arriving; units start
    /// 20 ms apart at most, less than the 33 ms between rebuilds, so the text
    /// is never more than `revealDuration` + 0.25 s behind the stream.
    private static let reveal = LTXFadeInAnimator.Configuration(
        duration: revealDuration,
        stagger: LTXStaggerSchedule(interval: 0.02, maxTotalDelay: 0.25),
        curve: .linear,
        // Enough for every chunk still fading at 30 rebuilds a second; past
        // the cap the oldest would show at once.
        maxBatches: 32,
    )

    convenience init() {
        self.init(viewProvider: ReusableViewProvider())
    }

    override init(viewProvider: ReusableViewProvider) {
        super.init(viewProvider: viewProvider)
        theme = Self.chatTheme(from: theme)
        // Code blocks and table cells copy this configuration, so text
        // streamed into them is revealed the same way.
        animator = LTXFadeInAnimator(configuration: Self.reveal)
        contextViewFadeDuration = Self.revealDuration
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(viewProvider:)")
    }

    /// The reply's look on top of the reader's font size: the system draws
    /// selection, blocks share one gap and list items keep a compact one,
    /// and inline code is quieter than the text around it. The list hands
    /// every reply and its sizing view this theme, so the two lay out alike.
    static func chatTheme(from base: MarkdownTheme) -> MarkdownTheme {
        var theme = base
        // A custom highlight color opts Litext out of UIKit's selection handles.
        // Let the system draw selection just as it does in other read-only text.
        theme.colors.selectionBackground = nil
        theme.spacings.paragraph = blockSpacing
        theme.spacings.list = 0
        // Inline code is quieter than the text around it: half its colours'
        // opacity. Code blocks have their own background and are left alone.
        theme.colors.codeBackground = halved(base.colors.codeBackground)
        return theme
    }

    override func textLabelView(
        _ label: TextLabelView,
        editMenuForSelection selection: NSRange,
        suggestedActions: [UIMenuElement],
    ) -> UIMenu? {
        ChatSelectionMenu.menu(for: label, selection: selection, suggestedActions: suggestedActions)
    }

    override func applyDocument(_ document: NSAttributedString, newContextViews: [UIView], animated: Bool) {
        let text = NSMutableAttributedString(attributedString: document)
        // A renderer's trailing paragraph must not add an empty line or a
        // second gap before the next transcript cell.
        while text.length > 0, [10, 13].contains((text.string as NSString).character(at: text.length - 1)) {
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
        // `colors.code` also colours a code block's plain text, so only the
        // inline runs, set in the inline code font, take the halved colour.
        let inlineCodeColor = Self.halved(theme.colors.code)
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { font, range, _ in
            guard let font = font as? UIFont, font == theme.fonts.codeInline else { return }
            text.addAttribute(.foregroundColor, value: inlineCodeColor, range: range)
        }
        var location = 0
        while location < text.length {
            let range = (text.string as NSString).paragraphRange(for: NSRange(location: location, length: 1))
            if let style = (text.attribute(.paragraphStyle, at: location, effectiveRange: nil)
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            {
                style.paragraphSpacingBefore = 0
                // All three list kinds use ListProcessor's indented paragraph
                // style and its independently configured list spacing. Keep it;
                // applying the ordinary block gap here expands every item.
                let usesListSpacing = style.headIndent > 0 && style.paragraphSpacing == theme.spacings.list
                style.paragraphSpacing = usesListSpacing ? theme.spacings.list : Self.blockSpacing
                if let attachment = text.attribute(.litextAttachment, at: location, effectiveRange: nil)
                    as? TextLabel.Attachment
                {
                    let marker = attachment.attributedStringRepresentation().string.trimmingCharacters(in: .whitespaces)
                    if marker.hasSuffix("."), let number = Int(marker.dropLast()), number > 50 {
                        // MarkdownView uses a 16 pt column for its number symbols.
                        // Larger ordinals are plain text, drawn left of that column;
                        // reserve their actual width so the label cannot cut them off.
                        let font = UIFont.monospacedDigitSystemFont(
                            ofSize: theme.fonts.footnote.pointSize,
                            weight: .regular,
                        )
                        let requiredIndent = ceil((marker as NSString).size(withAttributes: [.font: font]).width) + 8
                        let extra = max(0, requiredIndent - style.firstLineHeadIndent)
                        style.firstLineHeadIndent += extra
                        style.headIndent += extra
                    }
                }
                text.addAttribute(.paragraphStyle, value: style, range: range)
            }
            location = NSMaxRange(range)
        }
        if text.length > 0 {
            let last = (text.string as NSString).paragraphRange(for: NSRange(location: text.length - 1, length: 1))
            if let style = (text.attribute(.paragraphStyle, at: last.location, effectiveRange: nil)
                as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
            {
                style.paragraphSpacing = 0
                text.addAttribute(.paragraphStyle, value: style, range: last)
            }
        }
        super.applyDocument(text, newContextViews: newContextViews, animated: animated)
        spokenTextIsCurrent = false
        updateSpokenText()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        updateSpokenText()
    }

    /// Litext's label draws the reply but is no accessibility element, and
    /// this view is only a container, so VoiceOver never reached the text.
    /// The label reads it, code and tables as they would be copied; the view
    /// stays a container, so a code block's buttons are still reached on
    /// their own. Only a view in a window: the one measuring a row is never
    /// read, and is not made to spell its document out for every row.
    private func updateSpokenText() {
        guard window != nil, !spokenTextIsCurrent else { return }
        spokenTextIsCurrent = true
        let spoken = Self.spokenText(textLabelView.attributedText)
        textLabelView.isAccessibilityElement = !spoken.isEmpty
        textLabelView.accessibilityLabel = spoken.isEmpty ? nil : spoken
        textLabelView.accessibilityTraits = .staticText
    }

    /// The document as text: each attachment (a list marker, a code block, a
    /// table) as the text it stands for.
    static func spokenText(_ document: NSAttributedString) -> String {
        let text = NSMutableAttributedString(attributedString: document)
        text.enumerateAttribute(.litextAttachment, in: NSRange(location: 0, length: text.length), options: .reverse) {
            value, range, _ in
            guard let attachment = value as? TextLabel.Attachment else { return }
            text.replaceCharacters(in: range, with: attachment.attributedStringRepresentation())
        }
        return text.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The colour at half its own opacity, in light and dark alike.
    private static func halved(_ color: UIColor) -> UIColor {
        UIColor { traits in
            let resolved = color.resolvedColor(with: traits)
            return resolved.withAlphaComponent(resolved.cgColor.alpha * 0.5)
        }
    }
}

/// Keep UIKit's text services when it supplies them. Some versions only give
/// Litext's read-only input Copy and Select All; those still get useful actions.
@MainActor
enum ChatSelectionMenu {
    static func menu(for label: TextLabelView, selection: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        let responder = label.subviews.first(where: \.isFirstResponder) ?? label
        guard containsOnlyEditingCommands(suggestedActions, responder: responder) else { return nil }
        let text = label.attributedText.string as NSString
        guard selection.location != NSNotFound, selection.length > 0,
              selection.location <= text.length, selection.length <= text.length - selection.location
        else { return nil }
        let selected = text.substring(with: selection)
        var actions = [
            UIAction(
                title: String(localized: "Look Up"),
                image: UIImage(systemName: "text.book.closed"),
            ) { [weak label] _ in
                guard let label else { return }
                present(UIReferenceLibraryViewController(term: selected), from: label)
            },
        ]
        #if !targetEnvironment(macCatalyst)
            if #available(iOS 17.4, *) {
                actions.append(UIAction(
                    title: String(localized: "Translate"),
                    image: UIImage(systemName: "character.bubble"),
                ) { [weak label] _ in
                    guard let label, let window = label.window else { return }
                    let rect = label.convert(anchor(for: selection, in: label), to: window)
                    let page = UIHostingController(rootView: ChatSelectionTranslation(text: selected, anchor: rect))
                    page.modalPresentationStyle = .overFullScreen
                    page.view.backgroundColor = .clear
                    present(page, from: label, animated: false)
                })
            }
        #endif
        actions.append(
            UIAction(
                title: String(localized: "Share…"),
                image: UIImage(systemName: "square.and.arrow.up"),
            ) { [weak label] _ in
                guard let label else { return }
                let page = UIActivityViewController(activityItems: [selected], applicationActivities: nil)
                page.popoverPresentationController?.sourceView = label
                page.popoverPresentationController?.sourceRect = anchor(for: selection, in: label)
                present(page, from: label)
            },
        )
        return UIMenu(children: suggestedActions + [UIMenu(options: .displayInline, children: actions)])
    }

    /// UIKit includes commands it later hides because the first responder cannot
    /// perform them. Only an available service should suppress our fallback.
    private static func containsOnlyEditingCommands(_ elements: [UIMenuElement], responder: UIResponder) -> Bool {
        elements.allSatisfy { element in
            if let menu = element as? UIMenu {
                return containsOnlyEditingCommands(menu.children, responder: responder)
            }
            if let command = element as? UICommand {
                if !command.attributes.intersection([.disabled, .hidden]).isEmpty {
                    return true
                }
                guard responder.canPerformAction(command.action, withSender: nil) else { return true }
                return command.action == #selector(UIResponderStandardEditActions.copy(_:))
                    || command.action == #selector(UIResponderStandardEditActions.selectAll(_:))
            }
            if let action = element as? UIAction, !action.attributes.intersection([.disabled, .hidden]).isEmpty {
                return true
            }
            return [String(localized: "Copy"), String(localized: "Select All")].contains(element.title)
        }
    }

    private static func anchor(for selection: NSRange, in label: TextLabelView) -> CGRect {
        let selected = label.textLayout.rects(for: selection).map(label.viewRect(fromLayoutRect:))
            .reduce(CGRect.null) { $0.union($1) }
        let visible = label.window.map { label.convert($0.bounds, from: $0).intersection(label.bounds) } ?? label.bounds
        let anchor = selected.intersection(visible)
        return anchor.isNull || anchor.isEmpty ? visible : anchor
    }

    private static func present(_ page: UIViewController, from label: TextLabelView, animated: Bool = true) {
        guard label.window != nil else { return }
        var responder: UIResponder? = label
        while let current = responder {
            if let controller = current as? UIViewController {
                guard controller.presentedViewController == nil else { return }
                controller.present(page, animated: animated)
                return
            }
            responder = current.next
        }
    }
}

#if !targetEnvironment(macCatalyst)
/// A transparent host supplies the system translation popover with the selection's
/// position. Dismissing translation also dismisses the host, leaving no overlay.
@available(iOS 17.4, *)
private struct ChatSelectionTranslation: View {
    let text: String
    let anchor: CGRect
    @State private var isPresented = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Color.clear
            .frame(width: max(anchor.width, 1), height: max(anchor.height, 1))
            .translationPresentation(isPresented: $isPresented, text: text)
            .position(x: anchor.midX, y: anchor.midY)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .ignoresSafeArea()
            .onChange(of: isPresented) { _, visible in
                if !visible {
                    dismiss()
                }
            }
    }
}
#endif

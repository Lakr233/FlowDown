//
//  InputEditor+TextView.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

extension InputEditor {
    class TextEditorView: UITextView {
        init() {
            super.init(frame: .zero, textContainer: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(input: "\r", modifierFlags: .alternate, action: #selector(insertNewLine)),
                UIKeyCommand(input: "\r", modifierFlags: [], action: #selector(returnPressed)),
                UIKeyCommand(input: "\r", modifierFlags: .command, action: #selector(commandReturnPressed)),
            ]
        }

        var onReturnKeyPressed: (() -> Void) = {}
        var onCommandReturnKeyPressed: (() -> Void) = {}
        var onImagePasted: ((UIImage) -> Void) = { _ in }

        override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
            if action == #selector(paste(_:)) {
                // 不必检查剪贴板了 不然要弹窗
                return true
            }
            return super.canPerformAction(action, withSender: sender)
        }

        override func paste(_ sender: Any?) {
            if let image = UIPasteboard.general.image {
                onImagePasted(image)
                return
            }
            if EditorBehavior.pasteLargeTextContentAsFile,
               let text = UIPasteboard.general.string,
               text.count > 512
            {
                var superView: UIView? = self
                while superView != nil, !(superView is InputEditor) {
                    superView = superView?.superview
                }
                guard let editor = superView as? InputEditor else { return }
                editor.delegate?.onInputEditorPastingLargeTextAsDocument(content: text)
                return
            }
            super.paste(sender)
        }

        @objc private func insertNewLine() {
            insertText("\n")
        }

        @objc private func returnPressed() {
            onReturnKeyPressed()
        }

        @objc private func commandReturnPressed() {
            onCommandReturnKeyPressed()
        }
    }
}

extension InputEditor: UITextViewDelegate {
    public func textViewDidBeginEditing(_ textView: UITextView) {
        updateTextHeight()
        delegate?.onInputEditorBeginEditing()
        delegate?.onInputEditorTextChanged(text: textView.text)
        switchToRequiredStatus()
    }

    public func textViewDidEndEditing(_ textView: UITextView) {
        clearAttributedText()
        updateTextHeight()
        delegate?.onInputEditorTextChanged(text: textView.text)
        delegate?.onInputEditorEndEditing()
        switchToRequiredStatus()
    }

    public func textViewDidChange(_ textView: UITextView) {
        updatePlaceholderAlpha()
        updateTextHeight()
        delegate?.onInputEditorTextChanged(text: textView.text)
        switchToRequiredStatus()
    }

    public func textView(
        _ textView: UITextView,
        editMenuForTextIn _: NSRange,
        suggestedActions: [UIMenuElement]
    ) -> UIMenu? {
        let pasteboard = UIPasteboard.general
        let canPasteAttachment = pasteboard.hasStrings

        let actions: [UIAction] = [
            UIAction(title: String(localized: "Insert New Line")) { _ in
                textView.insertText("\n")
            },
            UIAction(
                title: String(localized: "Paste as Attachment"),
                attributes: canPasteAttachment ? [] : [.disabled],
            ) { [weak self] _ in
                self?.delegate?.onInputEditorPasteAsAttachmentTapped()
            },
            UIAction(title: String(localized: "More")) { [weak self] _ in
                self?.delegate?.onInputEditorToggleMoreButtonTapped()
            },
        ]
        return UIMenu(children: suggestedActions + actions)
    }

    public func textView(_ textView: UITextView, shouldChangeTextIn _: NSRange, replacementText text: String) -> Bool {
        #if !targetEnvironment(macCatalyst)
            if text == "\n", !EditorBehavior.useConfirmationOnSend {
                textView.resignFirstResponder()
                delegate?.onInputEditorSubmitButtonTapped()
                return false
            }
        #endif
        return true
    }

    func updatePlaceholderAlpha() {
        placeholderLabel.alpha = textView.text.isEmpty ? 1 : 0
    }

    func updateTextHeight() {
        let attrText = textView.attributedText ?? .init()
        let textHeight = TextMeasurementHelper.shared.measureSize(
            of: attrText,
            usingWidth: textView.frame.width,
        ).height
        let decision = ceil(max(textHeight, font.lineHeight))
        doWithAnimation { self.textHeight.send(decision) }
    }

    func clearAttributedText() {
        let currentText = textView.text
        textView.attributedText = NSAttributedString(
            string: currentText ?? "",
            attributes: [
                .font: UIFont.preferredFont(forTextStyle: .body),
                .foregroundColor: UIColor.label,
            ],
        )
    }
}

//
//  InputEditor+Layout.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import UIKit

extension InputEditor {
    func textLayoutHeight(_ input: CGFloat) -> CGFloat {
        var finalHeight = input
        finalHeight = max(font.lineHeight, finalHeight)
        finalHeight = min(finalHeight, maxTextEditorHeight)
        return ceil(finalHeight)
    }

    func switchToRequiredStatus() {
        assert(Thread.isMainThread)
        // avoid flickering animation if set twice
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(switchToRequiredStatusEx),
            object: nil
        )
        perform(#selector(switchToRequiredStatusEx), with: nil, afterDelay: 0.1)
    }

    @objc private func switchToRequiredStatusEx() {
        doWithAnimation { [self] in
            bossButton.transform = .identity
            moreButton.transform = .identity
            sendButton.transform = .identity
            voiceButton.transform = .identity
            if textView.isFirstResponder {
                if textView.text.isEmpty {
                    layoutStatus = .preFocusText
                } else {
                    layoutStatus = .editingText
                }
            } else {
                if textView.text.isEmpty {
                    layoutStatus = .standard
                } else {
                    layoutStatus = .editingText
                }
            }
        }
    }

    func layoutAsEditingText() {
        // textField | voiceButton | sendButton
        sendButton.frame = CGRect(
            x: bounds.width - inset.right - iconSize.width,
            y: bounds.height - iconSize.height - inset.bottom,
            width: iconSize.width,
            height: iconSize.height,
        )
        sendButton.alpha = 1
        moreButton.frame = CGRect(
            x: bounds.width - inset.right - iconSize.width,
            y: bounds.height - iconSize.height - inset.bottom,
            width: iconSize.width,
            height: iconSize.height,
        )
        defer { moreButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5) }
        moreButton.alpha = 0
        voiceButton.frame = CGRect(
            x: sendButton.frame.minX - iconSize.width - iconSpacing,
            y: sendButton.frame.minY,
            width: iconSize.width,
            height: iconSize.height,
        )
        voiceButton.alpha = 1

        let textLayoutHeight = textLayoutHeight(textHeight.value)
        textView.frame = CGRect(
            x: inset.left,
            y: (bounds.height - textLayoutHeight) / 2,
            width: voiceButton.frame.minX - inset.left - iconSpacing,
            height: textLayoutHeight,
        )
        placeholderLabel.frame = textView.frame

        // invisible element
        bossButton.frame = CGRect(
            x: 0 - inset.left - iconSize.width,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        bossButton.alpha = 0
    }

    func layoutAsPreEditingText() {
        defer { bossButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5) }
        defer { sendButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5) }

        // invisible elements
        bossButton.frame = CGRect(
            x: 0 - inset.left - iconSize.width,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        bossButton.alpha = 0

        moreButton.frame = CGRect(
            x: bounds.width - inset.right - iconSize.width,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        moreButton.alpha = 1
        voiceButton.frame = CGRect(
            x: moreButton.frame.minX - iconSize.width - iconSpacing,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        voiceButton.alpha = 1
        // reset textField width to fill the space
        let textLayoutHeight = textLayoutHeight(textHeight.value)
        textView.frame = CGRect(
            x: inset.left,
            y: (bounds.height - textLayoutHeight) / 2,
            width: voiceButton.frame.minX - inset.left - iconSpacing,
            height: textLayoutHeight,
        )
        textView.alpha = 1
        placeholderLabel.frame = textView.frame

        // invisible element
        sendButton.frame = CGRect(
            x: bounds.width + iconSpacing + inset.right,
            y: bounds.height - iconSize.height - inset.bottom,
            width: iconSize.width,
            height: iconSize.height,
        )
        sendButton.alpha = 0
    }

    func layoutAsStandard() {
        defer { sendButton.transform = CGAffineTransform(scaleX: 0.5, y: 0.5) }

        // captureButton | textField | voiceButton | moreButton
        bossButton.frame = CGRect(
            x: inset.left,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        bossButton.alpha = 1
        moreButton.frame = CGRect(
            x: bounds.width - inset.right - iconSize.width,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        moreButton.alpha = 1
        moreButton.transform = .identity
        voiceButton.frame = CGRect(
            x: moreButton.frame.minX - iconSize.width - iconSpacing,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        voiceButton.alpha = 1
        // reset textField width to fill the space
        let textLayoutHeight = textLayoutHeight(textHeight.value)
        textView.frame = CGRect(
            x: bossButton.frame.maxX + iconSpacing,
            y: (bounds.height - textLayoutHeight) / 2,
            width: voiceButton.frame.minX - bossButton.frame.maxX - iconSpacing * 2,
            height: textLayoutHeight,
        )
        textView.alpha = 1
        placeholderLabel.frame = textView.frame

        // invisible element
        sendButton.frame = CGRect(
            x: bounds.width + inset.right,
            y: inset.top,
            width: iconSize.width,
            height: iconSize.height,
        )
        sendButton.alpha = 0
    }
}

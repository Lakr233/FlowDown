//
//  RichEditorView+Delegates.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import AlertController
import Foundation
import ScrubberKit
import UIKit
import UniformTypeIdentifiers

extension RichEditorView: InputEditor.Delegate {
    func onInputEditorCaptureButtonTapped() {
        openCamera()
    }

    func onInputEditorPickAttachmentTapped() {
        openFilePicker()
    }

    func onInputEditorMicButtonTapped() {
        presentSpeechRecognition()
    }

    func onInputEditorToggleMoreButtonTapped() {
        endEditing(true)
        controlPanel.toggle()
    }

    func onInputEditorPasteAsAttachmentTapped() {
        guard importPasteboardContentAsAttachment() else {
            delegate?.onRichEditorError(NSLocalizedString("Unsupported format.", comment: ""))
            return
        }
    }

    func onInputEditorSubmitButtonTapped() {
        submitValues()
    }

    func onInputEditorBeginEditing() {
        quickSettingBar.scrollToAfterModelItem()
        controlPanel.close()
    }

    func onInputEditorEndEditing() {
        publishNewEditorStatus()
    }

    func onInputEditorPastingLargeTextAsDocument(content: String) {
        insertTextAttachment(content: content, preferredName: nil)
    }

    func onInputEditorPastingImage(image: UIImage) {
        process(image: image)
    }

    func onInputEditorTextChanged(text: String) {
        dropColorView.alpha = 0
        publishNewEditorStatus()
        guard text.isEmpty else { return }
        controlPanel.close()
    }
}

private extension RichEditorView {
    func importPasteboardContentAsAttachment() -> Bool {
        let pasteboard = UIPasteboard.general

        if pasteboard.hasImages, let image = pasteboard.image {
            process(image: image)
            return true
        }

        if let fileURL = extractFileURL(from: pasteboard) {
            process(file: fileURL)
            return true
        }

        if let remoteURL = extractRemoteURL(from: pasteboard) {
            let preferredName = suggestedName(for: remoteURL)
            insertTextAttachment(content: remoteURL.absoluteString, preferredName: preferredName)
            return true
        }

        if let text = extractText(from: pasteboard) {
            insertTextAttachment(content: text, preferredName: nil)
            return true
        }

        return false
    }

    func extractFileURL(from pasteboard: UIPasteboard) -> URL? {
        if let url = pasteboard.url, url.isFileURL {
            return url
        }
        if let urls = pasteboard.urls,
           let fileURL = urls.first(where: { $0.isFileURL })
        {
            return fileURL
        }
        for item in pasteboard.items {
            if let url = item[UTType.fileURL.identifier] as? URL {
                return url
            }
            if let data = item[UTType.fileURL.identifier] as? Data,
               let urlString = String(data: data, encoding: .utf8),
               let url = URL(string: urlString),
               url.isFileURL
            {
                return url
            }
        }
        return nil
    }

    func extractRemoteURL(from pasteboard: UIPasteboard) -> URL? {
        if let url = pasteboard.url, !url.isFileURL {
            return url
        }
        if let urls = pasteboard.urls,
           let remote = urls.first(where: { !$0.isFileURL })
        {
            return remote
        }
        for item in pasteboard.items {
            if let url = item[UTType.url.identifier] as? URL, !url.isFileURL {
                return url
            }
            if let data = item[UTType.url.identifier] as? Data,
               let urlString = String(data: data, encoding: .utf8),
               let url = URL(string: urlString),
               !url.isFileURL
            {
                return url
            }
        }
        return nil
    }

    func extractText(from pasteboard: UIPasteboard) -> String? {
        if let string = pasteboard.string, !string.isEmpty {
            return string
        }
        for item in pasteboard.items {
            for (typeIdentifier, value) in item {
                guard let type = UTType(typeIdentifier),
                      type.conforms(to: .plainText)
                else {
                    continue
                }
                if let string = value as? String, !string.isEmpty {
                    return string
                }
                if let data = value as? Data,
                   let string = String(data: data, encoding: .utf8),
                   !string.isEmpty
                {
                    return string
                }
            }
        }
        return nil
    }

    func insertTextAttachment(content: String, preferredName: String?) {
        guard !content.isEmpty else { return }
        let sanitizedName = sanitizedFileName(from: preferredName)
        let url = storage.absoluteURL(storage.random())
            .deletingLastPathComponent()
            .appendingPathComponent(sanitizedName)
            .appendingPathExtension("txt")
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
            process(file: url)
        } catch {
            delegate?.onRichEditorError(NSLocalizedString("Failed to save text.", comment: ""))
        }
    }

    func sanitizedFileName(from preferredName: String?) -> String {
        let fallback = NSLocalizedString("Pasteboard", comment: "") + "-\(UUID().uuidString)"
        guard var name = preferredName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !name.isEmpty
        else {
            return fallback
        }

        let invalidCharacters = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let components = name.components(separatedBy: invalidCharacters).filter { !$0.isEmpty }
        name = components.isEmpty ? fallback : components.joined(separator: "-")
        return name
    }

    func suggestedName(for url: URL) -> String? {
        let lastComponent = url.lastPathComponent
        if !lastComponent.isEmpty {
            return lastComponent
        }
        if let host = url.host, !host.isEmpty {
            return host
        }
        return nil
    }
}

extension RichEditorView: AttachmentsBar.Delegate {
    public func attachmentBarDidUpdateAttachments(_: [AttachmentsBar.Item]) {
        publishNewEditorStatus()
    }
}

extension RichEditorView: QuickSettingBar.Delegate {
    func quickSettingBarBuildModelSelectionMenu() -> [UIMenuElement] {
        delegate?.onRichEditorBuildModelSelectionMenu { [weak self] in
            self?.updateModelinfoFile()
        } ?? []
    }

    func quickSettingBarBuildAlternativeToolsMenu(
        isEnabled: Bool,
        requestReload: @escaping (Bool) -> Void
    ) -> [UIMenuElement] {
        delegate?.onRichEditorBuildAlternativeToolsMenu(isEnabled: isEnabled, requestReload: requestReload) ?? []
    }

    func updateModelinfoFile(postUpdate: Bool = true) {
        let newModel = delegate?.onRichEditorRequestCurrentModelName()
        doWithAnimation { self.quickSettingBar.setModelName(newModel) }
        let newModelIdentifier = delegate?.onRichEditorRequestCurrentModelIdentifier()
        quickSettingBar.setModelIdentifier(newModelIdentifier)
        var supportsToolCall = false
        if let newModelIdentifier {
            supportsToolCall = delegate?.onRichEditorCheckIfModelSupportsToolCall(newModelIdentifier) ?? false
        }
        quickSettingBar.updateToolCallAvailability(supportsToolCall)
        if postUpdate {
            delegate?.onRichEditorUpdateObject(object: collectObject())
        }
    }

    func quickSettingBarOnValueChagned() {
        publishNewEditorStatus()

        if quickSettingBar.toolsToggle.isOn {
            let newModelIdentifier = delegate?.onRichEditorRequestCurrentModelIdentifier()
            if let newModelIdentifier,
               let value = delegate?.onRichEditorCheckIfModelSupportsToolCall(newModelIdentifier),
               value
            { /* pass */ } else {
                quickSettingBar.toolsToggle.isOn = false
                let alert = AlertViewController(
                    title: "Error",
                    message: "This model does not support tool call or no model is selected.",
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: "OK", attribute: .accent) {
                        context.dispose()
                    }
                }
                parentViewController?.present(alert, animated: true)
            }
        }
    }
}

extension RichEditorView: ControlPanel.Delegate {
    func onControlPanelCameraButtonTapped() {
        openCamera()
    }

    func onControlPanelPickPhotoButtonTapped() {
        openPhotoPicker()
    }

    func onControlPanelPickFileButtonTapped() {
        openFilePicker()
    }

    func onControlPanelRequestWebScrubber() {
        let alert = AlertInputViewController(
            title: "Capture Web Content",
            message: "Please paste or enter the URL here, the web content will be fetched later.",
            placeholder: "https://",
            text: "",
            cancelButtonText: "Cancel",
            doneButtonText: "Capture",
        ) { [weak self] text in
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()),
                  url.host != nil
            else {
                let alert = AlertViewController(
                    title: "Error",
                    message: "Please enter a valid URL.",
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: "OK", attribute: .accent) {
                        context.dispose()
                    }
                }
                self?.parentViewController?.present(alert, animated: true)
                return
            }
            let indicator = AlertProgressIndicatorViewController(
                title: "Fetching Content",
            )
            self?.parentViewController?.present(indicator, animated: true)
            Scrubber.document(for: url) { [weak self] doc in
                Task { @MainActor in indicator.dismiss(animated: true) {
                    guard let doc else {
                        let alert = AlertViewController(
                            title: "Error",
                            message: "Failed to fetch the web content.",
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: "OK", attribute: .accent) {
                                context.dispose()
                            }
                        }
                        self?.parentViewController?.present(alert, animated: true)
                        return
                    }
                    let attachment = Object.Attachment(
                        type: .text,
                        name: doc.title,
                        previewImage: .init(),
                        imageRepresentation: .init(),
                        textRepresentation: doc.textDocument,
                        storageSuffix: UUID().uuidString,
                    )
                    self?.attachmentsBar.insert(item: attachment)
                }
                }
            }
        }
        parentViewController?.present(alert, animated: true)
    }

    func onControlPanelOpen() {
        quickSettingBar.hide()
        inputEditor.isControlPanelOpened = true
    }

    func onControlPanelClose() {
        quickSettingBar.show()
        inputEditor.isControlPanelOpened = false
    }
}

extension RichEditorView: UIDropInteractionDelegate {
    public func dropInteraction(_: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        var canHandleDrop = true
        for provider in session.items.map(\.itemProvider) {
            if session.localDragSession != nil {
                canHandleDrop = false
            }
            if canHandleDrop, provider.hasItemConformingToTypeIdentifier(UTType.folder.identifier) {
                canHandleDrop = false
            }
            if canHandleDrop, !provider.hasItemConformingToTypeIdentifier(UTType.item.identifier) {
                canHandleDrop = false
            }
        }
        return canHandleDrop
    }

    public func dropInteraction(_: UIDropInteraction, sessionDidUpdate _: UIDropSession) -> UIDropProposal {
        .init(operation: .copy)
    }

    public func dropInteraction(_: UIDropInteraction, sessionDidEnter _: UIDropSession) {
        UIView.animate(withDuration: 0.25) { self.dropColorView.alpha = 1 }
    }

    public func dropInteraction(_: UIDropInteraction, sessionDidExit _: any UIDropSession) {
        UIView.animate(withDuration: 0.25) { self.dropColorView.alpha = 0 }
    }

    public func dropInteraction(_: UIDropInteraction, sessionDidEnd _: UIDropSession) {
        UIView.animate(withDuration: 0.25) { self.dropColorView.alpha = 0 }
    }

    public func dropInteraction(_: UIDropInteraction, performDrop session: any UIDropSession) {
        let items = session.items
        UIView.animate(withDuration: 0.25) { self.dropColorView.alpha = 0 }
        for provider in items.map(\.itemProvider) {
            provider.loadFileRepresentation(
                forTypeIdentifier: UTType.item.identifier,
            ) { [weak self] url, _ in
                guard let self, let url else { return }
                let tempDir = disposableResourcesDir.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(
                    at: tempDir,
                    withIntermediateDirectories: true,
                )
                let targetURL = tempDir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: targetURL)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    process(file: targetURL)
                    Task.detached {
                        // we are now using disposableResourcesDir which is cleaned up on boot
                        // to avoid some background transcoding task failing
                        // we wait for 30 seconds before deleting the temp dir
                        try? await Task.sleep(for: .seconds(30))
                        try? FileManager.default.removeItem(at: tempDir)
                    }
                }
            }
        }
    }
}

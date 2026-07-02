//
//  RichEditorView+Delegates.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/17.
//

import AlertController
import Foundation
import PDFKit
import PhotosUI
import ScrubberKit
import UIKit
import UniformTypeIdentifiers

extension RichEditorView {
    func presentSpeechRecognition() {
        let controller = SimpleSpeechController()
        controller.callback = { [weak self] text in
            self?.inputEditor.set(
                text: (self?.inputEditor.textView.text ?? "") + text,
            )
            self?.inputEditor.textView.becomeFirstResponder()
        }
        controller.onErrorCallback = { [weak self] error in
            self?.delegate?.onRichEditorError(error.localizedDescription)
        }
        parentViewController?.present(controller, animated: true)
    }

    func openCamera() {
        guard let parent = parentViewController else { return }
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            delegate?.onRichEditorError(String(localized: "Camera is not available, please grant camera permission"))
            return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = self
        picker.allowsEditing = false
        picker.mediaTypes = ["public.image"]
        parent.present(picker, animated: true)
    }

    func openPhotoPicker() {
        guard let parent = parentViewController else { return }
        var config = PHPickerConfiguration()
        config.selectionLimit = 4
        config.filter = .images
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        parent.present(picker, animated: true)
    }

    func openFilePicker() {
        guard let parent = parentViewController else { return }
        let supportedTypes: [UTType] = [.data, .image, .text, .plainText, .pdf, .audio]
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: supportedTypes)
        picker.delegate = self
        picker.allowsMultipleSelection = true
        parent.present(picker, animated: true)
    }

    func process(image: UIImage) {
        guard let attachment = Object.Attachment(image: image, storage: storage) else {
            delegate?.onRichEditorError(NSLocalizedString("Failed to process image.", comment: ""))
            return
        }
        attachmentsBar.insert(item: attachment)
    }

    func process(file: URL) {
        if let fileType = UTType(filenameExtension: file.pathExtension),
           fileType.conforms(to: .audio)
        {
            process(audioFile: file)
            return
        }

        if let image = UIImage(contentsOfFile: file.path) {
            process(image: image)
            return
        }

        if file.pathExtension.lowercased() == "pdf" {
            processPDF(file: file)
            return
        }

        guard let attachment = Object.Attachment(file: file, storage: storage) else {
            delegate?.onRichEditorError(NSLocalizedString("Unsupported format.", comment: ""))
            return
        }
        if attachment.textRepresentation.count > 1_000_000 {
            delegate?.onRichEditorError(NSLocalizedString("Text too long.", comment: ""))
            return
        }
        attachmentsBar.insert(item: attachment)
    }

    private func process(audioFile url: URL) {
        guard let parentViewController else { return }
        Indicator.progress(title: "Encoding Audio", controller: parentViewController) { completion in
            let transcode = try await AudioTranscoder.transcode(url: url)
            let attachment = try await RichEditorView.Object.Attachment.makeAudioAttachment(
                transcoded: transcode,
                storage: self.storage,
                suggestedName: url.lastPathComponent,
            )
            await completion { @MainActor in
                self.attachmentsBar.insert(item: attachment)
            }
        }
    }

    func processPDF(file: URL) {
        guard let pdfDocument = PDFDocument(url: file) else {
            delegate?.onRichEditorError(NSLocalizedString("Failed to load PDF file.", comment: ""))
            return
        }

        let pageCount = pdfDocument.pageCount
        guard pageCount > 0 else {
            delegate?.onRichEditorError(NSLocalizedString("PDF file is empty.", comment: ""))
            return
        }

        let alert = AlertViewController(
            title: NSLocalizedString("Import PDF", comment: ""),
            message: String(format: NSLocalizedString("This PDF has %lld page(s). You can select whether to import it as text or convert it to images.", comment: ""), pageCount),
        ) { [weak self] context in
            context.addAction(title: NSLocalizedString("Cancel", comment: "")) {
                context.dispose()
            }
            context.addAction(title: NSLocalizedString("Import Text", comment: ""), attribute: .accent) {
                context.dispose {
                    guard let self else { return }
                    let attachment = Object.Attachment(
                        type: .text,
                        name: file.lastPathComponent,
                        previewImage: .init(),
                        imageRepresentation: .init(),
                        textRepresentation: pdfDocument.string ?? "",
                        storageSuffix: file.lastPathComponent,
                    )
                    if attachment.textRepresentation.count > 1_000_000 {
                        self.delegate?.onRichEditorError(NSLocalizedString("Text too long.", comment: ""))
                        return
                    }
                    self.attachmentsBar.insert(item: attachment)
                }
            }
            context.addAction(title: NSLocalizedString("Convert to Image", comment: ""), attribute: .accent) {
                context.dispose {
                    self?.convertPDFToImages(pdfDocument: pdfDocument, fileName: file.lastPathComponent)
                }
            }
        }
        parentViewController?.present(alert, animated: true)
    }

    func convertPDFToImages(pdfDocument: PDFDocument, fileName _: String) {
        let pageCount = pdfDocument.pageCount

        let indicator = AlertProgressIndicatorViewController(
            title: NSLocalizedString("Converting PDF", comment: ""),
        )
        parentViewController?.present(indicator, animated: true) { [weak self] in
            Task.detached(priority: .userInitiated) { [weak self] in
                var convertedImages: [UIImage] = []

                for pageIndex in 0 ..< pageCount {
                    guard let page = pdfDocument.page(at: pageIndex) else { continue }

                    let pageRect = page.bounds(for: .mediaBox)
                    let scaleFactor: CGFloat = 1.0
                    let targetSize = CGSize(
                        width: pageRect.width * scaleFactor,
                        height: pageRect.height * scaleFactor,
                    )

                    let renderer = UIGraphicsImageRenderer(size: targetSize)
                    let image = renderer.image { context in
                        UIColor.white.set()
                        context.fill(CGRect(origin: .zero, size: targetSize))

                        context.cgContext.translateBy(x: 0, y: targetSize.height)
                        context.cgContext.scaleBy(x: 1, y: -1)
                        context.cgContext.scaleBy(x: scaleFactor, y: scaleFactor)
                        context.cgContext.translateBy(x: -pageRect.minX, y: -pageRect.minY)
                        page.draw(with: .mediaBox, to: context.cgContext)
                    }

                    convertedImages.append(image)
                }

                let images = convertedImages
                await MainActor.run { [weak self] in
                    indicator.dismiss(animated: true) { [weak self] in
                        guard let self else { return }
                        guard !images.isEmpty else {
                            let alert = AlertViewController(
                                title: NSLocalizedString("Error", comment: ""),
                                message: NSLocalizedString("Failed to convert PDF pages to images.", comment: ""),
                            ) { context in
                                context.allowSimpleDispose()
                                context.addAction(title: NSLocalizedString("OK", comment: ""), attribute: .accent) {
                                    context.dispose()
                                }
                            }
                            parentViewController?.present(alert, animated: true)
                            return
                        }

                        for image in images {
                            process(image: image)
                        }

                        let successAlert = AlertViewController(
                            title: NSLocalizedString("Success", comment: ""),
                            message: String(format: NSLocalizedString("Successfully imported %lld page(s) from PDF.", comment: ""), images.count),
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: NSLocalizedString("OK", comment: ""), attribute: .accent) {
                                context.dispose()
                            }
                        }
                        parentViewController?.present(successAlert, animated: true)
                    }
                }
            }
        }
    }
}

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

    func quickSettingBarBuildAlternativeModelMenu() -> [UIMenuElement] {
        delegate?.onRichEditorBuildAlternativeModelMenu() ?? []
    }

    func quickSettingBarBuildAlternativeToolsMenu(isEnabled: Bool, requestReload: @escaping (Bool) -> Void) -> [UIMenuElement] {
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
        delegate?.onRichEditorTogglesUpdate(object: collectObject())

        if quickSettingBar.toolsToggle.isOn {
            let newModelIdentifier = delegate?.onRichEditorRequestCurrentModelIdentifier()
            if let newModelIdentifier,
               let value = delegate?.onRichEditorCheckIfModelSupportsToolCall(newModelIdentifier),
               value
            { /* pass */ } else {
                quickSettingBar.toolsToggle.isOn = false
                let alert = AlertViewController(
                    title: NSLocalizedString("Error", comment: ""),
                    message: NSLocalizedString("This model does not support tool call or no model is selected.", comment: ""),
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: NSLocalizedString("OK", comment: ""), attribute: .accent) {
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
            title: NSLocalizedString("Capture Web Content", comment: ""),
            message: NSLocalizedString("Please paste or enter the URL here, the web content will be fetched later.", comment: ""),
            placeholder: "https://",
            text: "",
            cancelButtonText: NSLocalizedString("Cancel", comment: ""),
            doneButtonText: NSLocalizedString("Capture", comment: ""),
        ) { [weak self] text in
            guard let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  let scheme = url.scheme,
                  ["http", "https"].contains(scheme.lowercased()),
                  url.host != nil
            else {
                let alert = AlertViewController(
                    title: NSLocalizedString("Error", comment: ""),
                    message: NSLocalizedString("Please enter a valid URL.", comment: ""),
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: NSLocalizedString("OK", comment: ""), attribute: .accent) {
                        context.dispose()
                    }
                }
                self?.parentViewController?.present(alert, animated: true)
                return
            }
            let indicator = AlertProgressIndicatorViewController(
                title: NSLocalizedString("Fetching Content", comment: ""),
            )
            self?.parentViewController?.present(indicator, animated: true)
            Scrubber.document(for: url) { [weak self] doc in
                Task { @MainActor in indicator.dismiss(animated: true) {
                    guard let doc else {
                        let alert = AlertViewController(
                            title: NSLocalizedString("Error", comment: ""),
                            message: NSLocalizedString("Failed to fetch the web content.", comment: ""),
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: NSLocalizedString("OK", comment: ""), attribute: .accent) {
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

extension RichEditorView.Object.Attachment {
    init?(image: UIImage, storage: TemporaryStorage) {
        guard let compressed = image.prepareAttachment() else { return nil }
        let suffix = storage.random() + ".jpeg"
        let url = storage.absoluteURL(suffix)
        do {
            try? FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
            )
            try? FileManager.default.removeItem(at: url)
            FileManager.default.createFile(atPath: url.path, contents: nil)
            try compressed.write(to: url)
        } catch {
            return nil
        }
        self.init(
            type: .image,
            name: "Image",
            previewImage: image.jpeg(.medium) ?? .init(),
            imageRepresentation: compressed,
            textRepresentation: "",
            storageSuffix: suffix,
        )
    }
}

extension RichEditorView.Object.Attachment {
    init?(file: URL, storage: TemporaryStorage) {
        guard let url = storage.duplicateIfNeeded(file) else { return nil }
        do {
            let content = try String(contentsOf: file)
            self.init(
                type: .text,
                name: file.lastPathComponent,
                previewImage: .init(),
                imageRepresentation: .init(),
                textRepresentation: content,
                storageSuffix: url.lastPathComponent,
            )
        } catch {
            return nil
        }
    }
}

extension RichEditorView.Object.Attachment {
    private static func fileExtension(from mimeType: String?) -> String? {
        guard let mimeType,
              let type = UTType(mimeType: mimeType),
              let ext = type.preferredFilenameExtension
        else {
            return nil
        }
        return ext
    }

    private static func formattedDuration(_ duration: TimeInterval) -> String {
        guard duration.isFinite,
              duration > 0
        else { return "0:00" }
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]
        return formatter.string(from: duration) ?? "0:00"
    }

    private static func normalizedName(_ suggested: String?, fileExtension: String) -> String {
        var base = suggested?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if base.isEmpty {
            base = NSLocalizedString("Audio Clip", comment: "")
        }
        if base.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            return base
        }
        return base + ".\(fileExtension)"
    }

    private static func writeAudioData(_ data: Data, to storage: TemporaryStorage, fileExtension: String) throws -> String {
        var suffix = storage.random()
        if !fileExtension.isEmpty {
            suffix += ".\(fileExtension)"
        }
        let url = storage.absoluteURL(suffix)
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try data.write(to: url, options: .atomic)
        return suffix
    }

    static func makeAudioAttachment(
        transcoded: AudioTranscoder.Result,
        storage: TemporaryStorage?,
        suggestedName: String?,
    ) async throws -> Self {
        let fileExtension = transcoded.format.isEmpty ? "m4a" : transcoded.format.lowercased()
        let formattedDuration = formattedDuration(transcoded.duration)
        let formattedSize = ByteCountFormatter.string(fromByteCount: Int64(transcoded.data.count), countStyle: .file)
        let durationLine = String(localized: "Duration • \(formattedDuration)")
        let sizeLine = String(localized: "Size • \(formattedSize)")
        let textDescription = [durationLine, sizeLine].joined(separator: "\n")

        let name = normalizedName(suggestedName, fileExtension: fileExtension)
        let suffix: String = if let storage {
            try writeAudioData(transcoded.data, to: storage, fileExtension: fileExtension)
        } else {
            UUID().uuidString + ".\(fileExtension)"
        }

        return .init(
            type: .audio,
            name: name,
            previewImage: .init(),
            imageRepresentation: transcoded.data,
            textRepresentation: textDescription,
            storageSuffix: suffix,
        )
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

//
//  RichEditorView+AttachmentImport.swift
//  RichEditor
//

import AlertController
import Foundation
import PDFKit
import PhotosUI
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
            // nothing references the rejected attachment, so drop its stored copy
            try? FileManager.default.removeItem(at: storage.absoluteURL(attachment.storageSuffix))
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
            title: "Import PDF",
            message: "This PDF has \(pageCount) page(s). You can select whether to import it as text or convert it to images.",
        ) { [weak self] context in
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Import Text", attribute: .accent) {
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
            context.addAction(title: "Convert to Image", attribute: .accent) {
                context.dispose {
                    self?.convertPDFToImages(pdfDocument: pdfDocument)
                }
            }
        }
        parentViewController?.present(alert, animated: true)
    }

    func convertPDFToImages(pdfDocument: PDFDocument) {
        let pageCount = pdfDocument.pageCount

        let indicator = AlertProgressIndicatorViewController(
            title: "Converting PDF",
        )
        parentViewController?.present(indicator, animated: true) { [weak self] in
            Task.detached(priority: .userInitiated) { [weak self] in
                var convertedImages: [UIImage] = []

                for pageIndex in 0 ..< pageCount {
                    guard let page = pdfDocument.page(at: pageIndex) else { continue }

                    let pageRect = page.bounds(for: .mediaBox)
                    let targetSize = CGSize(
                        width: pageRect.width,
                        height: pageRect.height,
                    )

                    let renderer = UIGraphicsImageRenderer(size: targetSize)
                    let image = renderer.image { context in
                        UIColor.white.set()
                        context.fill(CGRect(origin: .zero, size: targetSize))

                        context.cgContext.translateBy(x: 0, y: targetSize.height)
                        context.cgContext.scaleBy(x: 1, y: -1)
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
                                title: "Error",
                                message: "Failed to convert PDF pages to images.",
                            ) { context in
                                context.allowSimpleDispose()
                                context.addAction(title: "OK", attribute: .accent) {
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
                            title: "Success",
                            message: "Successfully imported \(images.count) page(s) from PDF.",
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: "OK", attribute: .accent) {
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

//
//  RichEditorView+PickerDelegates.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import Foundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

extension RichEditorView: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    public func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any],
    ) {
        picker.dismiss(animated: true)
        guard let image = info[.originalImage] as? UIImage else { return }
        process(image: image)
    }

    public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true)
    }
}

extension RichEditorView: PHPickerViewControllerDelegate {
    public func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        for result in results {
            result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] reading, _ in
                guard let image = reading as? UIImage else { return }
                Task { @MainActor [weak self] in
                    self?.process(image: image)
                }
            }
        }
    }
}

extension RichEditorView: UIDocumentPickerDelegate {
    public func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        for url in urls {
            // Files inside our own container are not security scoped, so a false
            // return only means there is no scope to stop later.
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            // Some imports, such as audio transcoding, read the file after this
            // returns and the scope has ended, so work from a local copy.
            let tempDir = disposableResourcesDir.appendingPathComponent(UUID().uuidString)
            try? FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true,
            )
            let targetURL = tempDir.appendingPathComponent(url.lastPathComponent)
            guard (try? FileManager.default.copyItem(at: url, to: targetURL)) != nil else {
                delegate?.onRichEditorError(NSLocalizedString("Unsupported format.", comment: ""))
                continue
            }
            process(file: targetURL)
            Task.detached {
                // same grace period as the drop handler, so background transcoding can finish reading
                try? await Task.sleep(for: .seconds(30))
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }
}

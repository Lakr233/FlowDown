//
//  RichEditorView+AttachmentFactories.swift
//  RichEditor
//

import Foundation
import UIKit

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
            // the file could not be read as text, so the copy made above is never used
            if url != file { try? FileManager.default.removeItem(at: url) }
            return nil
        }
    }
}

extension RichEditorView.Object.Attachment {
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

    private static func writeAudioData(
        _ data: Data,
        to storage: TemporaryStorage,
        fileExtension: String
    ) throws -> String {
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

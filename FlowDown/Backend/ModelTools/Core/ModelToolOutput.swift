//
//  ModelToolOutput.swift
//  FlowDown
//

import Foundation

/// What a call gives back: the text the model reads, and any images or
/// audio, which reach the model as attachments after every result of the
/// turn.
struct ModelToolOutput: Sendable {
    struct Attachment: Sendable {
        let name: String
        let data: Data
        let mimeType: String?
    }

    var text: String
    var images: [Attachment] = []
    var audio: [Attachment] = []

    /// Past this many characters the text is cut, with a note to the model.
    private static let textLimit = 64 * 1024

    /// The text cut at `textLimit`, with a note saying so.
    var truncatedText: String {
        guard text.count > Self.textLimit else { return text }
        return """
        \(String(text.prefix(Self.textLimit)))...
        [truncated output due to length exceeding \(Self.textLimit) characters]
        """
    }

    /// The text as the model receives it: truncated, and a short note in
    /// place of an empty result so the turn never reads as lost.
    var modelText: String {
        let truncated = truncatedText
        guard !truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return String(localized: "Tool executed successfully with no output")
        }
        return truncated
    }
}

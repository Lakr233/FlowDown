//
//  ReplyErrorDocument.swift
//  FlowDown
//

import Foundation

/// The document of the assistant message a failed turn leaves behind: the
/// error's description in a code fence that is never closed. Versions that
/// predate the error row render it as a code block; the message list shows
/// it as one red line that opens the details (`ErrorMessageView`).
///
/// A failure is written under the `error` info string, so it is told apart
/// from a reply even while the turn is still marked streaming. Failures saved
/// before that carry a bare fence, which a reply still being written could
/// also start with; those count only once the reply is done.
enum ReplyErrorDocument {
    static let prefix = "```error\n"
    static let legacyPrefix = "```\n"
    private static let fence = "```"

    /// The document a failed turn saves for `description`.
    static func document(for description: String) -> String {
        prefix + description
    }

    /// The error description `document` carries, or nil when it is a reply.
    /// `isStreaming`: the message is the reply still being written, in which
    /// a bare fence is only the start of a code block.
    static func description(in document: String, isStreaming: Bool = false) -> String? {
        let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: Substring
        if trimmed.hasPrefix(prefix) {
            body = trimmed.dropFirst(prefix.count)
        } else if !isStreaming, trimmed.hasPrefix(legacyPrefix) {
            body = trimmed.dropFirst(legacyPrefix.count)
        } else {
            return nil
        }
        // a fence that closes makes it a reply with a code block in it
        guard !body.contains(fence) else { return nil }
        let description = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return description.isEmpty ? nil : description
    }
}

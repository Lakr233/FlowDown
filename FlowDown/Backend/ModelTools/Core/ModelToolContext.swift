//
//  ModelToolContext.swift
//  FlowDown
//

import Foundation
import Storage

/// Where a call runs. In a conversation the tool gets the session and the
/// row that shows the call, so it can report progress there; Shortcuts
/// runs tools with neither.
struct ModelToolContext: @unchecked Sendable {
    let session: ConversationSession?
    let row: Message?

    static let headless = ModelToolContext(session: nil, row: nil)
}

//
//  ModelToolError.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import Foundation

/// Failures reported back to the model when a tool call cannot complete.
enum ModelToolError {
    static func failure(_ message: String) -> NSError {
        NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }

    /// The arguments are missing or malformed; `message` says which.
    static func invalidArguments(_ message: String) -> NSError {
        NSError(domain: String(localized: "Tool"), code: 400, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }
}

/// The user turned the call down on its approval card.
struct ModelToolDenial: Error {}

//
//  ShortcutError.swift
//  FlowDown
//
//  Created by qaq on 7/11/2025.
//

import AppIntents
import Foundation

enum ShortcutError: LocalizedError {
    case emptyMessage
    case modelUnavailable
    case emptyResponse
    case imageNotAllowed
    case imageNotSupportedByModel
    case invalidImage
    case invalidCandidates

    var errorDescription: String? {
        switch self {
        case .emptyMessage:
            String(localized: "Empty message.")
        case .modelUnavailable:
            String(localized: "Unable to find the selected model.")
        case .emptyResponse:
            String(localized: "The model did not return any content.")
        case .imageNotAllowed:
            String(localized: "This shortcut does not accept images.")
        case .imageNotSupportedByModel:
            String(localized: "The selected model does not support image inputs.")
        case .invalidImage:
            String(localized: "The provided image could not be processed.")
        case .invalidCandidates:
            String(localized: "At least one candidate is required.")
        }
    }
}

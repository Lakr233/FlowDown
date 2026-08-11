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
    case audioNotAllowed
    case audioNotSupportedByModel
    case invalidAudio
    case invalidCandidates
    case toolCallNotSupportedByModel

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
        case .audioNotAllowed:
            String(localized: "This shortcut does not accept audio.")
        case .audioNotSupportedByModel:
            String(localized: "The selected model does not support audio inputs.")
        case .invalidAudio:
            String(localized: "The provided audio could not be processed.")
        case .invalidCandidates:
            String(localized: "At least one candidate is required.")
        case .toolCallNotSupportedByModel:
            String(localized: "This model does not support tool call or no model is selected.")
        }
    }
}

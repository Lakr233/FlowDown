//
//  ModelManager+AAPL.swift
//  FlowDown
//
//  Created by Alan Ye on 6/30/25.
//  Updated by GPT-5 Codex on 11/11/25.
//

import ChatClientKit
import Foundation
import FoundationModels

// MARK: - Apple Intelligence Helpers

@available(iOS 26.0, macCatalyst 26.0, *)
extension AppleIntelligenceModel {
    private var systemAvailability: SystemLanguageModel.Availability {
        let availability = SystemLanguageModel.default.availability
        Logger.model.infoFile("[Apple Intelligence] availability: \(availability)")
        return availability
    }

    var availabilityStatus: String {
        switch systemAvailability {
        case .available:
            return String(localized: "Available")
        case .unavailable(.deviceNotEligible):
            return String(localized: "Device Not Eligible")
        case .unavailable(.appleIntelligenceNotEnabled):
            return String(localized: "Apple Intelligence Not Enabled")
        case .unavailable(.modelNotReady):
            return String(localized: "Model Not Ready")
        case let .unavailable(other):
            return String(localized: "Unavailable: \(String(describing: other))")
        @unknown default:
            return String(localized: "Unavailable")
        }
    }

    var availabilityDescription: String.LocalizationValue {
        switch systemAvailability {
        case .available:
            return "Apple Intelligence is available and ready to use on this device."
        case .unavailable(.deviceNotEligible):
            return "This device is not eligible for Apple Intelligence. Requires compatible hardware."
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Apple Intelligence is not enabled. Check your device settings."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence model is not ready. Try again later."
        case let .unavailable(other):
            return "Apple Intelligence is unavailable: \(String(describing: other))"
        @unknown default:
            return "Apple Intelligence availability is unknown."
        }
    }

    var modelDisplayName: String {
        canonicalName
    }
}

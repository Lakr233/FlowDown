//
//  AppleIntelligenceModel+Display.swift
//  FlowDown
//
//  Created by Alan Ye on 6/30/25.
//  Updated by GPT-5 Codex on 11/11/25.
//

import ChatClientKit
import Foundation
import FoundationModels

// MARK: - Names

/// Names for the two Apple Intelligence models. The switches in Settings and
/// the second line in the model menu use `local` and `privateCloudCompute`
/// under `family`; places with room for one line use the one-line names.
enum AppleIntelligenceModelNames {
    static var family: String {
        String(localized: "Apple Intelligence")
    }

    /// Its own key: the shared "Local" key reads differently in some
    /// languages (zh-Hans 本地, here 本机).
    static var local: String {
        String(localized: "Local (Apple Intelligence Model)", defaultValue: "Local")
    }

    /// Apple's product name, kept in English in every language.
    static var privateCloudCompute: String {
        String(localized: "Private Cloud Compute")
    }

    static var localOneLine: String {
        String(localized: "Apple Intelligence Local")
    }

    static var privateCloudComputeOneLine: String {
        String(localized: "Apple Intelligence Private Cloud Compute")
    }
}

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

    /// Why the model can't run, or nil when it's ready.
    var availabilityDescription: String.LocalizationValue? {
        switch systemAvailability {
        case .available:
            return nil
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
        AppleIntelligenceModelNames.localOneLine
    }
}

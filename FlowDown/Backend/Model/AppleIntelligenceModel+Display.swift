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

/// Names and copy for the two Apple Intelligence models.
enum AppleIntelligenceModelNames {
    /// The model's name everywhere it is picked or shown: the model menu, the
    /// model chip, the default model row, Shortcuts and the Runtime System
    /// Prompt. English in every language, so not localized.
    static let localModel = "Apple Intelligence Local"
    static let privateCloudComputeModel = "Apple Intelligence PCC"

    /// The Settings switch titles. Local has its own key: the shared "Local"
    /// key reads differently in some languages (zh-Hans 本地, here 本机).
    static var local: String {
        String(localized: "Local (Apple Intelligence Model)", defaultValue: "Local")
    }

    /// Apple's product name, kept in English in every language.
    static var privateCloudCompute: String {
        String(localized: "Private Cloud Compute")
    }
}

/// The text under each Settings switch and below the section. Swap the copy
/// here; the translations live in Localizable.xcstrings under these keys.
enum AppleIntelligenceModelDescriptions {
    static var local: String {
        String(localized: "Runs entirely on this device. Works offline, and your conversations never leave it.")
    }

    static var privateCloudCompute: String {
        String(localized: "A larger model running on Apple's private cloud. Apple doesn't store your requests. Needs an internet connection and has a daily limit.")
    }

    static var sectionFooter: String {
        String(localized: "Apple Intelligence models are built into your system. No API key or setup needed. Models you turn on here appear in the model menu.")
    }

    /// The footer, plus a line saying Private Cloud Compute needs the App
    /// Store build where this copy lacks its entitlement.
    static func sectionFooter(isEntitled: Bool) -> String {
        isEntitled
            ? sectionFooter
            : sectionFooter + "\n" + PrivateCloudComputePresentation.notEntitledText
    }

    /// The description, then why the model can't run on its own line.
    static func text(description: String, unavailableReason: String?) -> String {
        guard let unavailableReason, !unavailableReason.isEmpty else { return description }
        return description + "\n" + unavailableReason
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
        AppleIntelligenceModelNames.localModel
    }
}

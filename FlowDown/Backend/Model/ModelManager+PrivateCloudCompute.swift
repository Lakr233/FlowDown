//
//  ModelManager+PrivateCloudCompute.swift
//  FlowDown
//
//  Private Cloud Compute model settings: the switch key and Reasoning Effort.
//

import ChatClientKit
import ConfigurableKit
import Foundation

extension ModelManager {
    /// The Private Cloud Compute switch in Settings: whether the model menu
    /// lists the model, like the Local switch does for the on-device model.
    static let privateCloudComputeEnabledKey = "Model.Inference.AppleIntelligence.Cloud.Enabled"
    static let cloudReasoningEffortKey = "Model.Inference.AppleIntelligence.Cloud.ReasoningEffort"

    /// The Reasoning Effort menu for the cloud model, reusing the app's
    /// Low / Medium / High labels for the light / moderate / deep levels.
    static let cloudReasoningEffortConfigurableObject: ConfigurableObject = .init(
        icon: "brain.head.profile",
        title: "Reasoning Effort",
        key: cloudReasoningEffortKey,
        defaultValue: PrivateCloudComputeReasoningDepth.moderate.rawValue,
        annotation: .menu {
            PrivateCloudComputeReasoningDepth.allCases.map {
                .init(title: $0.effortTitle, rawValue: $0.rawValue)
            }
        },
    )

    var cloudReasoningDepth: PrivateCloudComputeReasoningDepth {
        let stored: String? = ConfigurableKit.value(forKey: Self.cloudReasoningEffortKey)
        return stored.flatMap(PrivateCloudComputeReasoningDepth.init(rawValue:)) ?? .moderate
    }
}

extension PrivateCloudComputeReasoningDepth {
    var effortTitle: String.LocalizationValue {
        switch self {
        case .light: "Low"
        case .moderate: "Medium"
        case .deep: "High"
        }
    }
}

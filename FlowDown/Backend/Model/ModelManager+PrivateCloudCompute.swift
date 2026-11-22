//
//  ModelManager+PrivateCloudCompute.swift
//  FlowDown
//
//  Apple Intelligence Cloud (Apple's Private Cloud Compute model) settings.
//

import ChatClientKit
import ConfigurableKit
import Foundation

extension ModelManager {
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

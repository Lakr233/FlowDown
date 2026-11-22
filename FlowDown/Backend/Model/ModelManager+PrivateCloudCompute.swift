//
//  ModelManager+PrivateCloudCompute.swift
//  FlowDown
//
//  Private Cloud Compute model settings: the switch key.
//

import ConfigurableKit
import Foundation

extension ModelManager {
    /// The Private Cloud Compute switch in Settings: whether the model menu
    /// lists the model, like the Local switch does for the on-device model.
    static let privateCloudComputeEnabledKey = "Model.Inference.AppleIntelligence.Cloud.Enabled"

    /// The retired Reasoning Effort menu for Private Cloud Compute, which now
    /// always uses deep reasoning. Also listed in `SettingsBackup.retiredKeys`.
    static let retiredCloudReasoningEffortKey = "Model.Inference.AppleIntelligence.Cloud.ReasoningEffort"

    /// Deletes the saved values of retired model settings. Runs at launch.
    static func removeRetiredSettings(storage: KeyValueStorage = ConfigurableKit.storage) {
        storage.setValue(nil, forKey: retiredCloudReasoningEffortKey)
    }
}

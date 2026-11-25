//
//  WelcomeExperience.swift
//  FlowDown
//
//  Created by ChatGPT on 2025/12/08.
//

import Foundation

enum WelcomeExperience {
    static let seenVersionKey = "WelcomeExperience.lastSeenVersion"

    static var currentVersion: String {
        "0"
    }

    static var shouldPresent: Bool {
        shouldPresent(defaults: .standard)
    }

    static func shouldPresent(defaults: UserDefaults) -> Bool {
        defaults.string(forKey: seenVersionKey) != currentVersion
    }

    static func markPresented(defaults: UserDefaults = .standard) {
        defaults.set(currentVersion, forKey: seenVersionKey)
    }

    /// Whether to show the welcome at launch. Someone who already has a model
    /// has used the app before: the welcome is recorded as seen without
    /// showing it. `hasExistingModel` is asked only while the welcome is
    /// still unseen.
    static func shouldPresentAtLaunch(
        defaults: UserDefaults = .standard,
        hasExistingModel: () -> Bool,
    ) -> Bool {
        guard shouldPresent(defaults: defaults) else { return false }
        if hasExistingModel() {
            markPresented(defaults: defaults)
            return false
        }
        return true
    }

    /// Any cloud or local model already on this device. Reads the lists the
    /// model manager loaded at launch; nothing is written.
    static var hasExistingModel: Bool {
        !ModelManager.shared.cloudModels.value.isEmpty
            || !ModelManager.shared.localModels.value.isEmpty
    }
}

//
//  WelcomeExperience.swift
//  FlowDown
//
//  Created by ChatGPT on 2025/12/08.
//

import Foundation
import Storage

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

    /// Any local model, or any cloud model with something filled in, already
    /// on this device. Reads the lists the model manager loaded at launch;
    /// nothing is written.
    static var hasExistingModel: Bool {
        hasExistingModel(
            cloudModels: ModelManager.shared.cloudModels.value,
            localModelCount: ModelManager.shared.localModels.value.count,
        )
    }

    static func hasExistingModel(cloudModels: [CloudModel], localModelCount: Int) -> Bool {
        localModelCount > 0 || cloudModels.contains { !isBlank($0) }
    }

    /// A cloud model nobody filled in: no model, endpoint, key or name. This
    /// is what Connect a Cloud Service creates before its editor opens.
    static func isBlank(_ model: CloudModel) -> Bool {
        model.model_identifier.isEmpty
            && model.endpoint.isEmpty
            && model.token.isEmpty
            && model.name.isEmpty
    }

    // MARK: - The Cloud Model the Welcome Created

    static let pendingCloudModelKey = "WelcomeExperience.pendingCloudModel"

    /// The cloud model Connect a Cloud Service created, kept until the
    /// welcome sees it again, so that one left blank can be removed even
    /// after the app was closed in its editor.
    static func pendingCloudModel(defaults: UserDefaults = .standard) -> CloudModel.ID? {
        defaults.string(forKey: pendingCloudModelKey)
    }

    static func setPendingCloudModel(_ identifier: CloudModel.ID?, defaults: UserDefaults = .standard) {
        if let identifier {
            defaults.set(identifier, forKey: pendingCloudModelKey)
        } else {
            defaults.removeObject(forKey: pendingCloudModelKey)
        }
    }

    private nonisolated(unsafe) static var hasDiscardedAtLaunch = false

    /// `discardBlankPendingCloudModel()` once per launch, before any welcome
    /// is open, so it never removes the model of an editor on screen.
    static func discardBlankPendingCloudModelAtLaunch() {
        guard !hasDiscardedAtLaunch else { return }
        hasDiscardedAtLaunch = true
        discardBlankPendingCloudModel()
    }

    /// Removes the cloud model the welcome created if it is still blank, and
    /// forgets it either way: one with anything filled in stays, as any model
    /// added in Settings does. Returns whether a model was removed.
    @discardableResult
    static func discardBlankPendingCloudModel(
        defaults: UserDefaults = .standard,
        lookup: (CloudModel.ID) -> CloudModel? = { ModelManager.shared.cloudModel(identifier: $0) },
        remove: (CloudModel.ID) -> Void = { ModelManager.shared.removeCloudModel(identifier: $0) },
    ) -> Bool {
        guard let identifier = pendingCloudModel(defaults: defaults) else { return false }
        setPendingCloudModel(nil, defaults: defaults)
        guard let model = lookup(identifier), isBlank(model) else { return false }
        remove(identifier)
        return true
    }
}

//
//  ModelManager+Menu.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/3/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import Foundation
import Storage
import UIKit

extension ModelManager {
    func buildModelSelectionMenu(
        currentSelection: ModelIdentifier? = nil,
        requiresCapabilities: Set<ModelCapabilities> = [],
        allowSelectionWithNone: Bool = false,
        onCompletion: @escaping (ModelIdentifier) -> Void,
        includeQuickActions: Bool,
    ) -> [UIMenuElement] {
        let localModels = ModelManager.shared.localModels.value.filter {
            !$0.model_identifier.isEmpty
        }.filter { requiresCapabilities.isSubset(of: $0.capabilities) }
        let cloudModels = ModelManager.shared.cloudModels.value.filter {
            !$0.model_identifier.isEmpty
        }.filter { requiresCapabilities.isSubset(of: $0.capabilities) }

        var appleIntelligenceAvailable = false
        if ModelManager.shared.appleIntelligenceEnabled,
           #available(iOS 26.0, macCatalyst 26.0, *),
           AppleIntelligenceModel.shared.isAvailable,
           requiresCapabilities.isSubset(of: modelCapabilities(
               identifier: AppleIntelligenceModel.shared.modelIdentifier,
           ))
        {
            appleIntelligenceAvailable = true
        }

        if localModels.isEmpty, cloudModels.isEmpty, !appleIntelligenceAvailable {
            return [
                UIAction(
                    title: String(localized: "(None)"),
                    attributes: [.disabled],
                ) { _ in },
            ]
        }

        var localBuildSections: [String: [(String, LocalModel)]] = [:]
        for item in localModels {
            localBuildSections[item.scopeIdentifier, default: []]
                .append((item.modelDisplayName, item))
        }
        var cloudBuildSections: [String: [(String, CloudModel)]] = [:]
        for item in cloudModels {
            cloudBuildSections[item.auxiliaryIdentifier, default: []]
                .append((item.modelDisplayName, item))
        }

        var localMenuChildren: [UIMenuElement] = []
        var localMenuChildrenOptions: UIMenu.Options = []
        if localModels.count < 4 { localMenuChildrenOptions.insert(.displayInline) }
        var cloudMenuChildren: [UIMenuElement] = []
        var cloudMenuChildrenOptions: UIMenu.Options = []
        if cloudModels.count < 4 { cloudMenuChildrenOptions.insert(.displayInline) }

        for key in localBuildSections.keys.sorted() {
            let items = localBuildSections[key] ?? []
            guard !items.isEmpty else { continue }
            let key = key.isEmpty ? String(localized: "Ungrouped") : key
            localMenuChildren.append(UIMenu(
                title: key,
                options: localMenuChildrenOptions,
                children: items.map { item in
                    UIAction(title: item.0, state: item.1.id == currentSelection ? .on : .off) { _ in
                        onCompletion(item.1.id)
                    }
                },
            ))
        }

        for key in cloudBuildSections.keys.sorted() {
            let items = cloudBuildSections[key] ?? []
            guard !items.isEmpty else { continue }
            let key = key.isEmpty ? String(localized: "Ungrouped") : key
            cloudMenuChildren.append(UIMenu(
                title: key,
                options: cloudMenuChildrenOptions,
                children: items.map { item in
                    UIAction(title: item.0, state: item.1.id == currentSelection ? .on : .off) { _ in
                        onCompletion(item.1.id)
                    }
                },
            ))
        }

        var finalChildren: [UIMenuElement] = []
        var finalOptions: UIMenu.Options = []
        if localMenuChildren.isEmpty || cloudMenuChildren.isEmpty || localMenuChildren.count + cloudMenuChildren.count < 10 {
            finalOptions.insert(.displayInline)
        }

        var leadingElements: [UIMenuElement] = []

        let totalSections = localBuildSections.count + cloudBuildSections.count
        let shouldShowRelatedModels = totalSections > 2

        if shouldShowRelatedModels, let currentSelection, !currentSelection.isEmpty {
            var relatedEntries: [(title: String, identifier: ModelIdentifier)] = []

            if let match = localModels.first(where: { $0.id == currentSelection }) {
                let groupKey = match.scopeIdentifier
                let peers = localBuildSections[groupKey] ?? []
                relatedEntries = peers.map { ($0.0, $0.1.id) }
            } else if let match = cloudModels.first(where: { $0.id == currentSelection }) {
                let groupKey = match.auxiliaryIdentifier
                let peers = cloudBuildSections[groupKey] ?? []
                relatedEntries = peers.map { ($0.0, $0.1.id) }
            }

            if relatedEntries.count > 1 {
                relatedEntries.sort { lhs, rhs in
                    if lhs.identifier == currentSelection { return true }
                    if rhs.identifier == currentSelection { return false }
                    return lhs.title < rhs.title
                }

                let relatedActions: [UIAction] = relatedEntries.map { entry in
                    UIAction(
                        title: entry.title,
                        state: entry.identifier == currentSelection ? .on : .off,
                    ) { _ in
                        onCompletion(entry.identifier)
                    }
                }
                leadingElements.append(contentsOf: relatedActions)
            }
        }

        if allowSelectionWithNone {
            finalChildren.append(UIAction(
                title: String(localized: "Use None"),
            ) { _ in
                onCompletion("")
            })
        }

        var appleIntelligenceMenu: UIMenuElement?
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            if appleIntelligenceAvailable {
                let appleAction = UIAction(
                    title: AppleIntelligenceModel.shared.modelDisplayName,
                    state: currentSelection == AppleIntelligenceModel.shared.modelIdentifier ? .on : .off,
                ) { _ in
                    onCompletion(AppleIntelligenceModel.shared.modelIdentifier)
                }
                appleIntelligenceMenu = UIMenu(
                    options: [.displayInline],
                    children: [appleAction],
                )
            }
        }

        if let appleIntelligenceMenu {
            finalChildren.append(appleIntelligenceMenu)
        }

        if !localMenuChildren.isEmpty {
            finalChildren.append(UIMenu(
                title: finalOptions.contains(.displayInline) ? "" : String(localized: "Local Models"),
                options: finalOptions,
                children: localMenuChildren,
            ))
        }
        if !cloudMenuChildren.isEmpty {
            finalChildren.append(UIMenu(
                title: finalOptions.contains(.displayInline) ? "" : String(localized: "Cloud Models"),
                options: finalOptions,
                children: cloudMenuChildren,
            ))
        }

        if !leadingElements.isEmpty {
            finalChildren.insert(contentsOf: leadingElements, at: 0)
        }

        if includeQuickActions {
            let taskMenu = buildModelSelectionMenu(
                currentSelection: Self.ModelIdentifier.defaultModelForAuxiliaryTask,
                requiresCapabilities: [],
                allowSelectionWithNone: !Self.ModelIdentifier.defaultModelForAuxiliaryTask.isEmpty,
                onCompletion: { identifier in
                    Self.ModelIdentifier.defaultModelForAuxiliaryTask = identifier
                },
                includeQuickActions: false,
            )
            let taskModelSelect = UIMenu(
                title: String(localized: "Task Model"),
                image: UIImage(systemName: "ellipsis.bubble"),
                children: taskMenu,
            )

            let auxVisionMenu = buildModelSelectionMenu(
                currentSelection: Self.ModelIdentifier.defaultModelForAuxiliaryVisualTask,
                requiresCapabilities: [.visual],
                allowSelectionWithNone: !Self.ModelIdentifier.defaultModelForAuxiliaryVisualTask.isEmpty,
                onCompletion: { identifier in
                    Self.ModelIdentifier.defaultModelForAuxiliaryVisualTask = identifier
                },
                includeQuickActions: false,
            )
            let auxVisionModelSelect = UIMenu(
                title: String(localized: "Auxiliary Visual Model"),
                image: UIImage(systemName: "eye"),
                children: auxVisionMenu,
            )

            let temperatureGroup = UIMenu(
                title: String(localized: "Imagination"),
                options: [.displayInline],
                children: ModelManager.temperaturePresets.map { preset -> UIAction in
                    let currentValue = Double(ModelManager.shared.temperature)
                    let isCurrent = abs(currentValue - preset.value) < 0.0001
                    return UIAction(
                        title: String(localized: preset.title),
                        image: UIImage(systemName: preset.icon),
                        state: isCurrent ? .on : .off,
                    ) { _ in
                        ModelManager.shared.temperature = Float(preset.value)
                    }
                },
            )
            let quickMenu = UIMenu(
                title: String(localized: "Parameters"),
                options: [.displayInline],
                children: [UIMenu(
                    title: String(localized: "Inference Settings"),
                    children: [
                        taskModelSelect,
                        auxVisionModelSelect,
                        temperatureGroup,
                    ],
                )],
            )
            finalChildren.append(quickMenu)
        }

        return finalChildren
    }
}

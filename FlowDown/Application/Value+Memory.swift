//
//  Value+Memory.swift
//  FlowDown
//
//  Created by GPT-5 Codex on 11/6/25.
//

import ConfigurableKit
import Foundation

enum MemoryProactiveProvisionScope: String, CaseIterable, Codable {
    case off
    case pastDay
    case pastWeek
    case pastMonth
    case pastYear
    case recent15
    case recent30
    case all

    var icon: String {
        switch self {
        case .off:
            "nosign"
        case .pastDay:
            "sun.max"
        case .pastWeek:
            "calendar"
        case .pastMonth:
            "calendar"
        case .pastYear:
            "calendar.badge.clock"
        case .recent15:
            "list.number"
        case .recent30:
            "list.number"
        case .all:
            "tray.full"
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .off:
            "Off"
        case .pastDay:
            "Past Day"
        case .pastWeek:
            "Past Week"
        case .pastMonth:
            "Past Month"
        case .pastYear:
            "Past Year"
        case .recent15:
            "Latest 15 Items"
        case .recent30:
            "Latest 30 Items"
        case .all:
            "All Memories"
        }
    }

    var briefDescription: String.LocalizationValue {
        switch self {
        case .off:
            "Proactive memory sharing is disabled."
        case .pastDay:
            "Memories saved within the past 24 hours."
        case .pastWeek:
            "Memories saved within the past 7 days."
        case .pastMonth:
            "Memories saved within the past 30 days."
        case .pastYear:
            "Memories saved within the past year."
        case .recent15:
            "The most recent 15 memories."
        case .recent30:
            "The most recent 30 memories."
        case .all:
            "All stored memories."
        }
    }

    enum Filter {
        case none
        case timeInterval(TimeInterval)
        case count(Int)
        case all
    }

    var filter: Filter {
        switch self {
        case .off:
            .none
        case .pastDay:
            .timeInterval(24 * 60 * 60)
        case .pastWeek:
            .timeInterval(7 * 24 * 60 * 60)
        case .pastMonth:
            .timeInterval(30 * 24 * 60 * 60)
        case .pastYear:
            .timeInterval(365 * 24 * 60 * 60)
        case .recent15:
            .count(15)
        case .recent30:
            .count(30)
        case .all:
            .all
        }
    }
}

enum MemoryProactiveProvisionSetting {
    static let storageKey = "app.memory.proactive.provision.scope"

    static let configurableObject: ConfigurableObject = .init(
        icon: "brain.head.profile",
        title: "Proactive Memory Context",
        explain: "Choose how we proactively shares stored memories with the model during conversations and automations. This includes system Shortcuts.",
        key: storageKey,
        defaultValue: MemoryProactiveProvisionScope.off.rawValue,
        annotation: .list {
            MemoryProactiveProvisionScope.allCases.map { scope in
                .init(
                    icon: scope.icon,
                    title: scope.title,
                    rawValue: scope.rawValue
                )
            }
        }
    )

    static var currentScope: MemoryProactiveProvisionScope {
        let raw: String? = ConfigurableKit.value(forKey: storageKey)
        if let raw, let scope = MemoryProactiveProvisionScope(rawValue: raw) {
            return scope
        }
        return .off
    }
}

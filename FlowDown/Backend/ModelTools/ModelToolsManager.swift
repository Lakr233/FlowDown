//
//  ModelToolsManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

/// The built-in tools, and the set a conversation offers the model.
final class ModelToolsManager {
    static let shared = ModelToolsManager()

    let tools: [any ConfigurableModelTool]

    private init() {
        var registry: [any ConfigurableModelTool] = [
            MTAddCalendarTool(),
            MTQueryCalendarTool(),

            MTAddReminderTool(),
            MTQueryReminderTool(),
            MTUpdateReminderTool(),
            MTCompleteReminderTool(),
            MTDeleteReminderTool(),

            MTWebSearchTool(),
            MTWebScraperTool(),
        ]

        // location services are not available on macOS
        #if !targetEnvironment(macCatalyst)
            registry.append(MTLocationTool())
        #endif

        registry += [
            MTStoreMemoryTool(),
            MTRecallMemoryTool(),
            MTListMemoriesTool(),
            MTUpdateMemoryTool(),
            MTDeleteMemoryTool(),
        ]

        tools = registry

        assert(Set(tools.map { $0.functionName }).count == tools.count)

        ModelToolAuthorization.migrateLegacySetting()
    }

    var enabledTools: [any ConfigurableModelTool] {
        tools.filter { $0.isEnabled }
    }

    var memoryTools: [any ConfigurableModelTool] {
        tools.filter { $0.group == .memory }
    }

    var calendarTools: [any ConfigurableModelTool] {
        tools.filter { $0.group == .calendar }
    }

    var reminderTools: [any ConfigurableModelTool] {
        tools.filter { $0.group == .reminders }
    }

    /// The tools settings and the tools menu list one by one.
    var configurableTools: [any ConfigurableModelTool] {
        tools.filter { $0.group == nil }
    }

    var enabledMemoryWritingTools: [any ConfigurableModelTool] {
        enabledTools.filter { $0 is MTStoreMemoryTool || $0 is MTUpdateMemoryTool || $0 is MTDeleteMemoryTool }
    }

    var canStoreMemory: Bool {
        enabledTools.contains { $0 is MTStoreMemoryTool }
    }

    static func shouldExposeMemory(
        modelWillExecuteTools: Bool,
        enabledTools: [any ModelTool],
    ) -> Bool {
        modelWillExecuteTools && enabledTools.contains { ($0 as? any ConfigurableModelTool)?.group == .memory }
    }

    /// The enabled built-in tools, then the tools of every connected MCP
    /// server, as one inference offers them.
    func makeToolSet() async -> ModelToolSet {
        var result: [any ModelTool] = enabledTools.map { $0 as any ModelTool }
        await result.append(contentsOf: MCPService.shared.listServerTools().map { $0 as any ModelTool })
        return ModelToolSet(tools: result)
    }
}

// MARK: - Settings

extension ModelToolsManager {
    private static var calendarValue: Bool {
        get { shared.calendarTools.contains { $0.isEnabled } }
        set { for tool in shared.calendarTools { tool.isEnabled = newValue } }
    }

    static var calendarToggle: ConfigurableToggleActionView {
        .init().with {
            $0.actionBlock = { calendarValue = $0 }
            $0.configure(icon: UIImage(systemName: "calendar"))
            $0.configure(title: "Calendar")
            $0.configure(description: "Allows LLM to save events to your calendar.")
            $0.boolValue = calendarValue
        }
    }

    private static var remindersValue: Bool {
        get { shared.reminderTools.contains { $0.isEnabled } }
        set { for tool in shared.reminderTools { tool.isEnabled = newValue } }
    }

    static var remindersToggle: ConfigurableToggleActionView {
        .init().with {
            $0.actionBlock = { remindersValue = $0 }
            $0.configure(icon: UIImage(systemName: "checklist"))
            $0.configure(title: "Reminders")
            $0.configure(description: "Allows LLM to create reminders in your system Reminders.")
            $0.boolValue = remindersValue
        }
    }
}

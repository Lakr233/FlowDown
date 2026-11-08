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

        let memoryTools: [any ConfigurableModelTool] = [
            MTStoreMemoryTool(),
            MTRecallMemoryTool(),
            MTListMemoriesTool(),
            MTUpdateMemoryTool(),
            MTDeleteMemoryTool(),
        ]
        registry.append(contentsOf: memoryTools)

        tools = registry

        #if DEBUG
            var registeredToolNames: Set<String> = []
            for tool in tools {
                assert(registeredToolNames.insert(tool.functionName).inserted)
            }
        #endif

        ModelToolAuthorization.migrateLegacySetting()
    }

    var enabledTools: [any ConfigurableModelTool] {
        tools.filter { $0.isEnabled }
    }

    func tools(in group: ModelToolGroup) -> [any ConfigurableModelTool] {
        tools.filter { $0.group == group }
    }

    var memoryTools: [any ConfigurableModelTool] {
        tools(in: .memory)
    }

    var calendarTools: [any ConfigurableModelTool] {
        tools(in: .calendar)
    }

    var reminderTools: [any ConfigurableModelTool] {
        tools(in: .reminders)
    }

    /// The tools settings and the tools menu list one by one.
    var configurableTools: [any ConfigurableModelTool] {
        tools.filter { $0.group == nil }
    }

    var enabledMemoryWritingTools: [any ConfigurableModelTool] {
        enabledTools.filter { Self.isMemoryWritingTool($0) }
    }

    var canStoreMemory: Bool {
        enabledTools.contains { $0 is MTStoreMemoryTool }
    }

    static func isMemoryTool(_ tool: any ModelTool) -> Bool {
        (tool as? any ConfigurableModelTool)?.group == .memory
    }

    static func isMemoryWritingTool(_ tool: any ModelTool) -> Bool {
        tool is MTStoreMemoryTool || tool is MTUpdateMemoryTool || tool is MTDeleteMemoryTool
    }

    static func shouldExposeMemory(
        modelWillExecuteTools: Bool,
        enabledTools: [any ModelTool],
    ) -> Bool {
        guard modelWillExecuteTools else { return false }
        return enabledTools.contains { isMemoryTool($0) }
    }

    /// The enabled built-in tools, then the tools of every connected MCP
    /// server, as one inference offers them.
    func makeToolSet(includingMCP: Bool = true) async -> ModelToolSet {
        var result: [any ModelTool] = enabledTools.map { $0 as any ModelTool }
        if includingMCP {
            await result.append(contentsOf: MCPService.shared.listServerTools().map { $0 as any ModelTool })
        }
        return ModelToolSet(tools: result)
    }
}

// MARK: - Settings

extension ModelToolsManager {
    static var calendarValue: Bool {
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

    static var remindersValue: Bool {
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

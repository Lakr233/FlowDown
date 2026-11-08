//
//  ModelToolAuthorization.swift
//  FlowDown
//

import ConfigurableKit
import Foundation

/// Whether a call waits for the user. One setting decides it: while
/// Require Confirmation is on, a call that reads or changes the user's
/// private data, or runs a tool from an MCP server, asks first; searching
/// the web or reading memories never does.
enum ModelToolAuthorization {
    private static let requiresConfirmationKey = "wiki.qaq.ModelTools.RequiresConfirmation"
    private static let requiresConfirmationByDefault = true
    /// The switch this setting replaced, which skipped every dialog.
    static let legacySkipConfirmationKey = "ModelToolsManager.skipConfirmation"

    static var requiresConfirmation: Bool {
        get { ConfigurableKit.value(forKey: requiresConfirmationKey) ?? requiresConfirmationByDefault }
        set { ConfigurableKit.set(value: newValue, forKey: requiresConfirmationKey) }
    }

    static let configurableObject = ConfigurableObject(
        icon: "hand.raised",
        title: "Require Confirmation",
        explain: "Asks before tools use your calendar, reminders, or location, and before tools from MCP servers run.",
        key: requiresConfirmationKey,
        defaultValue: requiresConfirmationByDefault,
        annotation: .toggle,
    )

    static func needsApproval(_ tool: any ModelTool) -> Bool {
        requiresConfirmation && tool.access != .general
    }

    /// Someone who had turned confirmations off keeps them off.
    static func migrateLegacySetting(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: legacySkipConfirmationKey) != nil else { return }
        if defaults.bool(forKey: legacySkipConfirmationKey) {
            requiresConfirmation = false
        }
        defaults.removeObject(forKey: legacySkipConfirmationKey)
    }
}

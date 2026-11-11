//
//  Value+InlineActivitySteps.swift
//  FlowDown
//

import Combine
import ConfigurableKit
import Foundation

/// Whether an activity summary in the chat lists every step under its title:
/// each thought as its whole text and each call as a line. Off by default,
/// where a summary is its title and, while a call runs, that call's line.
/// The trace opens from the title either way.
///
/// A new key: the retired "Collapse Reasoning Content" toggle's stored value
/// meant something else and stays skipped (`SettingsBackup.retiredKeys`).
enum InlineActivityStepsSetting {
    static let storageKey = "app.chat.activity.inline.steps"
    static let defaultValue = false

    static let configurableObject: ConfigurableObject = .init(
        icon: "text.bubble",
        title: "Show Thinking and Tool Calls",
        explain: "Show the model's thinking and each tool call as text in the chat while it replies. Trace is still available.",
        key: storageKey,
        defaultValue: defaultValue,
        annotation: .toggle,
    )

    static func isEnabled() -> Bool {
        (ConfigurableKit.value(forKey: storageKey) as Bool?) ?? defaultValue
    }

    static func setEnabled(_ enabled: Bool) {
        ConfigurableKit.set(value: enabled, forKey: storageKey)
    }

    /// The current value, then each change.
    static var publisher: AnyPublisher<Bool, Never> {
        ConfigurableKit.publisher(forKey: storageKey, type: Bool.self)
            .map { $0 ?? defaultValue }
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

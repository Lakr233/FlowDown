//
//  Value+CodeBlockCollapse.swift
//  FlowDown
//

import Combine
import ConfigurableKit
import Foundation
import MarkdownView

enum CodeBlockCollapseSetting {
    static let storageKey = "app.interface.CodeBlockCollapsible"
    static let defaultValue = true

    private static var cancellables: Set<AnyCancellable> = []

    static let collapsibilityDidChange = PassthroughSubject<Bool, Never>()

    static let configurableObject: ConfigurableObject = .init(
        icon: "chevron.up.chevron.down",
        title: "Collapsible Code Blocks",
        explain: "Collapse long code blocks into a short, scrollable preview that expands on demand. Turn this off to always show code blocks in full.",
        key: storageKey,
        defaultValue: defaultValue,
        annotation: .toggle,
    )

    static func subscribeToConfigurableItem() {
        assert(cancellables.isEmpty)
        ConfigurableKit.publisher(forKey: storageKey, type: Bool.self)
            .receive(on: RunLoop.main)
            .sink { input in
                let enabled = input ?? defaultValue
                guard CodeBlockCollapse.isEnabled != enabled else { return }
                CodeBlockCollapse.isEnabled = enabled
                collapsibilityDidChange.send(enabled)
            }
            .store(in: &cancellables)
    }
}

//
//  Value+LiveActivity.swift
//  FlowDown
//
//  Created by AI on 1/6/26.
//

import Combine
import ConfigurableKit
import Foundation

enum LiveActivitySetting {
    static let storageKey = "app.liveactivity.enabled"
    private static var cancellables: Set<AnyCancellable> = []

    static let configurableObject: ConfigurableObject = .init(
        icon: "bolt.horizontal.circle",
        title: "Enable Live Activity",
        explain: "Show a Live Activity while streaming in the background.",
        key: storageKey,
        defaultValue: false,
        annotation: .toggle,
    )

    static func isEnabled() -> Bool {
        (ConfigurableKit.value(forKey: storageKey) as Bool?) ?? false
    }

    static func setEnabled(_ enabled: Bool) {
        ConfigurableKit.set(value: enabled, forKey: storageKey)
    }

    static func subscribeToConfigurableItem() {
        assert(cancellables.isEmpty)

        // Keep Live Activity toggle consistent with Audio Feedback.
        ConfigurableKit.publisher(forKey: StreamAudioEffectSetting.storageKey, type: Int.self)
            .ensureMainThread()
            .sink { rawValue in
                let mode = rawValue.flatMap(StreamAudioEffectSetting.init(rawValue:)) ?? .off
                if mode == .off {
                    LiveActivitySetting.setEnabled(false)
                }
            }
            .store(in: &cancellables)

        // When the toggle itself changes, refresh Live Activity state.
        ConfigurableKit.publisher(forKey: storageKey, type: Bool.self)
            .ensureMainThread()
            .sink { _ in
                Task { @MainActor in
                    ConversationSessionManager.shared.refreshLiveActivity()
                }
            }
            .store(in: &cancellables)
    }
}

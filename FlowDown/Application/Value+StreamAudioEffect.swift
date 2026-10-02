//
//  Value+DialTuneMode.swift
//  FlowDown
//
//  Created by AI on 1/6/26.
//

import Combine
import ConfigurableKit
import Foundation

enum StreamAudioEffectSetting: Int, CaseIterable {
    case off = 0
    case random = 11
    case custom = 12

    var icon: String {
        switch self {
        case .off: "speaker.slash"
        case .random: "shuffle"
        case .custom: "music.note"
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .off: "Off"
        case .random: "Random Dial Tone"
        case .custom: "Custom Audio"
        }
    }

    var audioIndex: Int? {
        switch self {
        case .off: nil
        case .random: Int.random(in: 0 ... 9)
        case .custom: nil
        }
    }
}

extension StreamAudioEffectSetting {
    static let storageKey = "app.audio.stream.effect"
    private static var cancellables: Set<AnyCancellable> = []

    static let configurableObject: ConfigurableObject = .init(
        icon: "speaker.wave.2",
        title: "Audio Feedback",
        explain: "Play audio feedback during inference output. This helps determine if a task is complete when running in the background.",
        key: storageKey,
        defaultValue: StreamAudioEffectSetting.off.rawValue,
        annotation: .menu {
            StreamAudioEffectSetting.allCases.map { item -> MenuAnnotation.Option in
                .init(
                    icon: item.icon,
                    title: item.title,
                    rawValue: item.rawValue,
                )
            }
        },
    )

    static func subscribeToConfigurableItem() {
        assert(cancellables.isEmpty)
        ConfigurableKit.publisher(forKey: storageKey, type: Int.self)
            .sink { _ in
                Task { @MainActor in
                    SoundEffectPlayer.shared.updateMode()
                }
            }
            .store(in: &cancellables)
    }

    static func configuredMode() -> StreamAudioEffectSetting {
        guard
            let rawValue: Int = ConfigurableKit.value(forKey: storageKey),
            let mode = StreamAudioEffectSetting(rawValue: rawValue)
        else {
            return .off
        }
        return mode
    }
}

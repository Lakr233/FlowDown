//
//  Value+MLX.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import Combine
import ConfigurableKit
import Foundation
import MLX
import UIKit

extension MLX.GPU {
    static let storageKey = "wiki.qaq.MLX.GPU.cacheSize"
    static var cancellables = Set<AnyCancellable>()
    static let isSupportedKey = "Device.isMlxSupported"
    static var isSupported: Bool {
        ConfigurableKit.value(forKey: isSupportedKey) ?? false
    }

    enum CacheSizeLimit: String, CaseIterable {
        case notAllowed
        case allowedInForeground
        #if targetEnvironment(macCatalyst)
            case unrestricted
        #endif

        var title: String.LocalizationValue {
            switch self {
            case .notAllowed: return "Not Allowed"
            case .allowedInForeground: return "Allowed in Foreground"
            #if targetEnvironment(macCatalyst)
                case .unrestricted: return "Unrestricted"
            #endif
            }
        }
    }

    static let configurableObject: ConfigurableObject = .init(
        icon: "aqi.medium",
        title: "Inference Cache",
        explain: "Set the strategy for handling runtime resource cache. Allowing the use of cache can speed up inference and save energy, but may cause the software to close unexpectedly.",
        key: storageKey,
        defaultValue: CacheSizeLimit.notAllowed.rawValue,
        annotation: .menu {
            CacheSizeLimit.allCases.map { item in
                MenuAnnotation.Option(title: item.title, rawValue: item.rawValue)
            }
        },
        availabilityRequirement: .match(key: isSupportedKey, value: true),
    )

    static func subscribeToConfigurableItem() {
        #if targetEnvironment(simulator) || arch(x86_64)
            return
        #else
            assert(cancellables.isEmpty)
            let value: String? = ConfigurableKit.value(forKey: Self.storageKey)
            if value == nil { ConfigurableKit.set(value: CacheSizeLimit.notAllowed.rawValue, forKey: Self.storageKey) }
            ConfigurableKit.publisher(forKey: storageKey, type: String.self)
                .sink { _ in onApplicationBecomeActivate() }
                .store(in: &cancellables)
        #endif
    }

    private static var configuredCacheSizeLimit: CacheSizeLimit {
        CacheSizeLimit(rawValue: ConfigurableKit.value(forKey: storageKey) ?? "") ?? .notAllowed
    }

    static func onApplicationResignActivate() {
        guard isSupported else { return }
        switch configuredCacheSizeLimit {
        case .notAllowed, .allowedInForeground:
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        #if targetEnvironment(macCatalyst)
            case .unrestricted:
                MLX.Memory.cacheLimit = .max
        #endif
        }
    }

    static func onApplicationBecomeActivate() {
        guard isSupported else { return }
        switch configuredCacheSizeLimit {
        case .notAllowed:
            MLX.Memory.cacheLimit = 0
            MLX.Memory.clearCache()
        case .allowedInForeground:
            MLX.Memory.cacheLimit = .max
        #if targetEnvironment(macCatalyst)
            case .unrestricted:
                MLX.Memory.cacheLimit = .max
        #endif
        }
    }
}

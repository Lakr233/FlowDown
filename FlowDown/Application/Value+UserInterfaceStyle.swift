//
//  Value+UserInterfaceStyle.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/26/25.
//

import Combine
import ConfigurableKit
import Foundation
import UIKit

extension UIUserInterfaceStyle {
    static var cases: [UIUserInterfaceStyle] = [
        .light,
        .dark,
        .unspecified,
    ]

    var icon: String {
        switch self {
        case .light: "sun.max"
        case .dark: "moon"
        case .unspecified: "circle"
        @unknown default: "circle"
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .light: "Light"
        case .dark: "Dark"
        case .unspecified: "System"
        @unknown default: "System"
        }
    }

    var catalystAppearance: NSObject? {
        switch self {
        case .light:
            (NSClassFromString("NSAppearance") as? NSObject.Type)?
                .perform(NSSelectorFromString("appearanceNamed:"), with: "NSAppearanceNameAqua")?
                .takeUnretainedValue() as? NSObject
        case .dark:
            (NSClassFromString("NSAppearance") as? NSObject.Type)?
                .perform(NSSelectorFromString("appearanceNamed:"), with: "NSAppearanceNameDarkAqua")?
                .takeUnretainedValue() as? NSObject
        default: nil
        }
    }
}

extension UIUserInterfaceStyle {
    static let storageKey = "app.appearance.UIUserInterfaceStyle"
    private static var cancellables: Set<AnyCancellable> = []

    static let configurableObject: ConfigurableObject = .init(
        icon: "lightbulb",
        title: "Appearance",
        explain: "Override system appearance, either light or dark.",
        key: storageKey,
        defaultValue: UIUserInterfaceStyle.unspecified.rawValue,
        annotation: .menu {
            UIUserInterfaceStyle.cases.map { item -> MenuAnnotation.Option in
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
            .sink { input in
                let style = input.flatMap(UIUserInterfaceStyle.init(rawValue:)) ?? .unspecified
                UIView.animate(withDuration: 0.25) {
                    apply(style: style)
                }
            }
            .store(in: &cancellables)

        reapplyConfiguredStyle()
    }

    static func apply(style: Self) {
        #if targetEnvironment(macCatalyst)
            let appearance = style.catalystAppearance
            let setAppearanceSelector = Selector(("setAppearance:"))
            guard let app = (NSClassFromString("NSApplication") as? NSObject.Type)?
                .value(forKey: "sharedApplication") as? NSObject,
                app.responds(to: setAppearanceSelector)
            else { return }
            app.perform(setAppearanceSelector, with: appearance)
        #else
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .forEach { $0.overrideUserInterfaceStyle = style }
        #endif
    }

    static func configuredStyle() -> UIUserInterfaceStyle {
        guard
            let rawValue: Int = ConfigurableKit.value(forKey: storageKey),
            let style = UIUserInterfaceStyle(rawValue: rawValue)
        else {
            return .unspecified
        }
        return style
    }

    static func reapplyConfiguredStyle() {
        apply(style: configuredStyle())
    }
}

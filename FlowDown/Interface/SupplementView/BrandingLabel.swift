//
//  BrandingLabel.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import AlertController
import ConfigurableKit
import GlyphixTextFx
import UIKit

class BrandingLabel: GlyphixTextLabel {
    /// The name shown when no branding is set: the app's localized display name,
    /// so Chinese users see the Chinese app name and everyone else sees FlowDown.
    nonisolated static func defaultBrandingValue(
        localizedInfoDictionary: [String: Any]? = Bundle.main.localizedInfoDictionary,
    ) -> String {
        if let name = localizedInfoDictionary?["CFBundleDisplayName"] as? String,
           !name.isEmpty
        { return name }
        return "FlowDown"
    }

    static let configurableObject = ConfigurableObject(
        icon: "pencil",
        title: "Edit Branding Name",
        explain: "Change the branding name display in the app. Leave it empty to use FlowDown.",
        key: "BrandingLabel.Text",
        defaultValue: BrandingLabel.defaultBrandingValue(),
        annotation: .action { controller in
            let alert = AlertInputViewController(
                title: "Edit Branding Name",
                message: "Change the branding name display in the app. Leave it empty to use FlowDown.",
                placeholder: .init(BrandingLabel.defaultBrandingValue()),
                text: BrandingLabel.readBrandingValue(),
                cancelButtonText: "Cancel",
                doneButtonText: "Set",
            ) { text in
                BrandingLabel.setBrandingValue(text)
                NotificationCenter.default.post(name: .brandingLabelNeedsUpdate, object: nil)
            }
            controller.present(alert, animated: true)
        },
    )

    static func setBrandingValue(_ value: String) {
        UserDefaults.standard.set(value, forKey: BrandingLabel.configurableObject.key)
    }

    static func readBrandingValue() -> String {
        if let value = UserDefaults.standard.string(forKey: BrandingLabel.configurableObject.key),
           !value.isEmpty
        { return value }
        return defaultBrandingValue()
    }

    init() {
        super.init(frame: .zero)
        textColor = .label
        font = .systemFont(ofSize: UIFont.labelFontSize, weight: .semibold)
        isBlurEffectEnabled = true
        countsDown = true
        text = BrandingLabel.defaultBrandingValue()

        setContentHuggingPriority(.required, for: .vertical)
        setContentCompressionResistancePriority(.required, for: .vertical)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(updateBrandingLabel),
            name: .brandingLabelNeedsUpdate,
            object: nil,
        )
        updateBrandingLabel()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc func updateBrandingLabel() {
        text = BrandingLabel.readBrandingValue()
        sizeToFit() // Ensure the label resizes to fit the new text
    }
}

extension Notification.Name {
    static let brandingLabelNeedsUpdate = Notification.Name("BrandingLabelNeedsUpdate")
}

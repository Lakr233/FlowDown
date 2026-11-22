//
//  InferenceController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/2/25.
//

import AlertController
import ChatClientKit
import ConfigurableKit
import UIKit

extension SettingController.SettingContent {
    class InferenceController: StackScrollController {
        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Inference")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
        }

        private let defaultConversationModel = ConfigurableInfoView().with {
            $0.configure(icon: UIImage(systemName: "quote.bubble"))
            $0.configure(title: "Default Model")
            $0.configure(description: "The model used for new conversations.")
        }

        private let appleIntelligenceToggle = ConfigurableBooleanBlockView(storage: .init(
            key: ModelManager.appleIntelligenceEnabledKey,
            defaultValue: true,
            storage: UserDefaultKeyValueStorage(suite: .standard),
        )).with {
            $0.configure(icon: UIImage(systemName: "apple.intelligence"))
            $0.configure(title: AppleIntelligenceModelNames.local)
        }

        private let privateCloudComputeToggle = ConfigurableBooleanBlockView(storage: .init(
            key: ModelManager.privateCloudComputeEnabledKey,
            defaultValue: true,
            storage: UserDefaultKeyValueStorage(suite: .standard),
        )).with {
            $0.configure(icon: UIImage(systemName: "icloud"))
            $0.configure(title: AppleIntelligenceModelNames.privateCloudCompute)
        }

        override func setupContentViews() {
            super.setupContentViews()

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Conversation",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(defaultConversationModel)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableObject(
                    icon: "character.bubble",
                    title: "Chat Template",
                    explain: "The template used for new conversations. You can customize the system prompt and other parameters here. Also known as assistant.",
                    ephemeralAnnotation: .page {
                        ChatTemplateListController()
                    },
                ).createView(),
            )
            stackView.addArrangedSubview(SeparatorView())

            defer { updateDefaultModelinfoFile() }

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Parameters",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.defaultPromptConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.extraPromptConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ModelManager.includeDynamicSystemInfo.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "The above parameters will be applied to all conversations.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            // Apple Intelligence Models: one switch per model, which decides
            // whether the model menu lists it. The text under a switch
            // describes the model, then says why it can't run on a new line.
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionHeaderView().with(
                        header: "Apple Intelligence Models",
                    ),
                ) { $0.bottom /= 2 }
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(appleIntelligenceToggle)
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(privateCloudComputeToggle)
                stackView.addArrangedSubview(SeparatorView())

                stackView.addArrangedSubviewWithMargin(
                    ConfigurableSectionFooterView().with(
                        footer: .init(AppleIntelligenceModelDescriptions.sectionFooter),
                    ),
                ) { $0.top /= 2 }
                stackView.addArrangedSubview(SeparatorView())

                updateAppleIntelligenceModels()

                appleIntelligenceToggle.onUpdated = { [weak self] isOn in
                    ModelManager.shared.appleIntelligenceEnabled = isOn
                    self?.updateDefaultModelinfoFile()
                }
                privateCloudComputeToggle.onUpdated = { [weak self] isOn in
                    ModelManager.shared.privateCloudComputeEnabled = isOn
                    self?.updateDefaultModelinfoFile()
                }
            }
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            updateDefaultModelinfoFile()
            updateAppleIntelligenceModels()
        }

        func updateAppleIntelligenceModels() {
            if #available(iOS 26.0, macCatalyst 26.0, *) {
                let localReason = PrivateCloudComputeCenter.shared.isOnDeviceModelAvailable
                    ? nil
                    : AppleIntelligenceModel.shared.availabilityDescription.map { String(localized: $0) }
                appleIntelligenceToggle.configure(description: .init(AppleIntelligenceModelDescriptions.text(
                    description: AppleIntelligenceModelDescriptions.local,
                    unavailableReason: localReason,
                )))
            }
            privateCloudComputeToggle.configure(description: .init(AppleIntelligenceModelDescriptions.text(
                description: AppleIntelligenceModelDescriptions.privateCloudCompute,
                unavailableReason: PrivateCloudComputeCenter.shared.unavailableText,
            )))
            // Without the entitlement (the Developer ID Mac build) the model
            // can never run here, so the switch shows off and can't be used.
            // The stored preference is left as it is.
            let isEntitled = PrivateCloudComputeCenter.shared.isEntitled
            privateCloudComputeToggle.switchView.isEnabled = isEntitled
            if !isEntitled {
                privateCloudComputeToggle.switchView.setOn(false, animated: false)
            }
        }

        func updateDefaultModelinfoFile() {
            ModelManager.shared.checkDefaultModels()

            func displayName(for id: ModelManager.ModelIdentifier) -> String {
                if let localModel = ModelManager.shared.localModel(identifier: id) {
                    return localModel.model_identifier
                }
                if let cloudModel = ModelManager.shared.cloudModel(identifier: id) {
                    return cloudModel.modelFullName
                }
                return String(localized: "Not Configured")
            }

            func configureModelRow(_ row: ConfigurableInfoView, id: ModelManager.ModelIdentifier) {
                if #available(iOS 26.0, macCatalyst 26.0, *), id == AppleIntelligenceModel.shared.modelIdentifier {
                    row.configure(value: AppleIntelligenceModel.shared.modelDisplayName)
                    if !AppleIntelligenceModel.shared.isAvailable {
                        row.configure(description: "Status: \(AppleIntelligenceModel.shared.availabilityStatus)")
                    }
                } else if id == PrivateCloudComputeCenter.modelIdentifier {
                    row.configure(value: AppleIntelligenceModelNames.privateCloudComputeModel)
                    if let unavailableText = PrivateCloudComputeCenter.shared.unavailableText {
                        row.configure(description: .init(unavailableText))
                    }
                } else {
                    row.configure(value: displayName(for: id))
                }
            }

            configureModelRow(defaultConversationModel, id: ModelManager.ModelIdentifier.defaultModelForConversation)
            defaultConversationModel.use { [weak self] in
                guard let self else { return [] }
                return ModelManager.shared.buildModelSelectionMenu(
                    currentSelection: ModelManager.ModelIdentifier.defaultModelForConversation,
                    requiresCapabilities: [],
                    allowSelectionWithNone: true,
                    onCompletion: { [weak self] identifier in
                        ModelManager.ModelIdentifier.defaultModelForConversation = identifier
                        self?.updateDefaultModelinfoFile()
                    },
                )
            }
        }
    }
}

private class ConfigurableBooleanBlockView: ConfigurableToggleView {
    var onUpdated: ((Bool) -> Void)?

    override func valueChanged() {
        super.valueChanged()
        onUpdated?(boolValue)
    }
}

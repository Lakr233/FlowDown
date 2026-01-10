import AlertController
import Foundation
import Storage
import UIKit

extension CloudModelEditorController {
    static func isEmptyJsonObject(_ jsonString: String) -> Bool {
        guard
            let data = jsonString.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return false }
        return jsonObject.isEmpty
    }

    static func prettyPrintedJson(from raw: String) -> String? {
        guard
            let data = raw.data(using: .utf8),
            let jsonObject = try? JSONSerialization.jsonObject(with: data)
        else { return nil }
        guard JSONSerialization.isValidJSONObject(jsonObject),
              let formattedData = try? JSONSerialization.data(
                  withJSONObject: jsonObject,
                  options: [.prettyPrinted, .sortedKeys],
              ) else { return nil }
        return String(data: formattedData, encoding: .utf8)
    }
}

extension CloudModelEditorController {
    private enum ReasoningParametersType: String, CaseIterable {
        case reasoning
        case enableThinking = "enable_thinking"
        case thinkingMode = "thinking_mode"
        case thinking

        var title: String.LocalizationValue { "Use \(rawValue) Key" }

        func insert(to dic: inout [String: Any]) {
            switch self {
            case .enableThinking: dic[rawValue] = true
            case .thinkingMode: dic[rawValue] = ["type": "enabled"]
            case .thinking: dic[rawValue] = ["type": "enabled"]
            case .reasoning: dic[rawValue] = ["enabled": true]
            }
        }
    }

    private enum ReasoningBudgetPreset: String, CaseIterable {
        case minimal
        case low
        case medium
        case high

        var thinkingBudgetTokens: Int {
            switch self {
            case .minimal: 512
            case .low: 1024
            case .medium: 4096
            case .high: 8192
            }
        }

        var title: String.LocalizationValue { "Set Budget to \(thinkingBudgetTokens) Tokens" }
    }

    private enum ReasoningEffortPreset: String, CaseIterable {
        case xhigh
        case high
        case medium
        case low
        case minimal
        case none
    }

    func buildExtraBodyEditorMenu(controller: JsonEditorController) -> UIMenu {
        .init(children: [UIDeferredMenuElement.uncached { [weak self] comp in
            guard let self else { comp([]); return }
            var children: [UIMenuElement] = []
            children.append(buildReasoningMenu(controller: controller))
            children.append(buildSamplingMenu(controller: controller))
            children.append(buildModalitiesMenu(controller: controller))
            children.append(buildProviderMenu(controller: controller))
            comp(children)
        }])
    }

    private func buildReasoningMenu(controller: JsonEditorController) -> UIMenu {
        let reasoningActions = ReasoningParametersType.allCases.map { type -> UIAction in
            UIAction(title: String(localized: type.title), image: UIImage(systemName: "key")) { _ in
                let dictionary = controller.currentDictionary
                let existingKeys = ReasoningParametersType.allCases.filter { dictionary.keys.contains($0.rawValue) }
                if !existingKeys.isEmpty, existingKeys != [type] {
                    let alert = AlertViewController(
                        title: "Duplicated Content",
                        message: "Another key already exists, which usually causes errors. You can choose to replace it.",
                    ) { context in
                        context.addAction(title: "Cancel") { context.dispose() }
                        context.addAction(title: "Replace", attribute: .accent) {
                            context.dispose {
                                controller.updateValue {
                                    for existing in existingKeys {
                                        $0.removeValue(forKey: existing.rawValue)
                                    }
                                    type.insert(to: &$0)
                                }
                            }
                        }
                    }
                    controller.present(alert, animated: true)
                } else {
                    controller.updateValue { type.insert(to: &$0) }
                }
            }
        }

        let reasoningKeysMenu = UIMenu(
            title: String(localized: "Reasoning Keys"),
            image: UIImage(systemName: "key"),
            options: [.displayInline],
            children: reasoningActions,
        )

        let reasoningBudgetMenu: UIMenu = {
            let dictionary = controller.currentDictionary
            let existingKeys = ReasoningParametersType.allCases.filter { dictionary.keys.contains($0.rawValue) }
            guard existingKeys.count == 1, let key = existingKeys.first else {
                let title: String.LocalizationValue = existingKeys.isEmpty
                    ? "Unavailable - No Reasoning Key"
                    : "Unavailable - Multiple Reasoning Keys"
                return UIMenu(
                    title: String(localized: "Reasoning Budget"),
                    image: UIImage(systemName: "gauge"),
                    options: [.displayInline],
                    children: [UIAction(
                        title: String(localized: title),
                        image: UIImage(systemName: "xmark.circle"),
                        attributes: [.disabled],
                    ) { _ in }],
                )
            }

            let budgetActions = ReasoningBudgetPreset.allCases.map { effort in
                UIAction(title: String(localized: effort.title)) { _ in
                    controller.updateValue { dictionary in
                        switch key {
                        case .thinkingMode, .thinking, .enableThinking:
                            dictionary["thinking_budget"] = effort.thinkingBudgetTokens
                        case .reasoning:
                            var value = dictionary[key.rawValue, default: [:]] as? [String: Any] ?? [:]
                            value["max_tokens"] = effort.thinkingBudgetTokens
                            dictionary[key.rawValue] = value
                        }
                    }
                }
            }
            return UIMenu(
                title: String(localized: "Reasoning Budget"),
                image: UIImage(systemName: "gauge"),
                options: [.displayInline],
                children: budgetActions,
            )
        }()

        let reasoningEffortMenu: UIMenu = {
            let effortActions = ReasoningEffortPreset.allCases.map { effort -> UIAction in
                UIAction(
                    title: String(localized: "Set \("reasoning.effort") to \(effort.rawValue)"),
                    image: UIImage(systemName: "bolt.circle"),
                ) { _ in
                    let dictionary = controller.currentDictionary
                    let existingKeys = ReasoningParametersType.allCases.filter { dictionary.keys.contains($0.rawValue) }

                    let apply: () -> Void = {
                        controller.updateValue { dictionary in
                            for existing in existingKeys where existing != .reasoning {
                                dictionary.removeValue(forKey: existing.rawValue)
                            }

                            var reasoning = dictionary["reasoning"] as? [String: Any] ?? [:]
                            reasoning["effort"] = effort.rawValue
                            dictionary["reasoning"] = reasoning
                        }
                    }

                    if !existingKeys.isEmpty, existingKeys != [.reasoning] {
                        let alert = AlertViewController(
                            title: "Duplicated Content",
                            message: "Another key already exists, which usually causes errors. You can choose to replace it.",
                        ) { context in
                            context.addAction(title: "Cancel") { context.dispose() }
                            context.addAction(title: "Replace", attribute: .accent) {
                                context.dispose {
                                    apply()
                                }
                            }
                        }
                        controller.present(alert, animated: true)
                    } else {
                        apply()
                    }
                }
            }

            return UIMenu(
                title: String(localized: "Reasoning Effort"),
                image: UIImage(systemName: "bolt.circle"),
                options: [.displayInline],
                children: effortActions,
            )
        }()

        return UIMenu(
            title: String(localized: "Reasoning Parameters"),
            image: UIImage(systemName: "brain.head.profile"),
            children: [reasoningKeysMenu, reasoningBudgetMenu, reasoningEffortMenu],
        )
    }

    private func buildSamplingMenu(controller: JsonEditorController) -> UIMenu {
        let actions: [UIAction] = [
            makeDictionaryAction(
                title: "Add \("temperature")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["temperature"] = Double(ModelManager.shared.temperature) },
            makeDictionaryAction(
                title: "Add \("top_p")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["top_p"] = 0.9 },
            makeDictionaryAction(
                title: "Add \("top_k")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["top_k"] = 40 },
            makeDictionaryAction(
                title: "Add \("top_a")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["top_a"] = 0.0 },
            makeDictionaryAction(
                title: "Add \("presence_penalty")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["presence_penalty"] = 0.0 },
            makeDictionaryAction(
                title: "Add \("frequency_penalty")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["frequency_penalty"] = 0.5 },
            makeDictionaryAction(
                title: "Add \("repetition_penalty")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["repetition_penalty"] = 1.0 },
            makeDictionaryAction(
                title: "Add \("min_p")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["min_p"] = 0.0 },
            makeDictionaryAction(
                title: "Add \("max_tokens")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["max_tokens"] = 4096 },
            makeDictionaryAction(
                title: "Add \("seed")",
                systemImage: "sparkles",
                controller: controller,
            ) { $0["seed"] = 114_514 },
        ]

        return UIMenu(
            title: String(localized: "Sampling Parameters"),
            image: UIImage(systemName: "slider.horizontal.3"),
            children: actions,
        )
    }

    private func buildModalitiesMenu(controller: JsonEditorController) -> UIMenu {
        let inputActions: [UIAction] = [
            makeModalitiesAction(
                title: "Add modalities: text",
                key: "modalities",
                value: "text",
                systemImage: "text.bubble",
                controller: controller,
            ),
            makeModalitiesAction(
                title: "Add modalities: image",
                key: "modalities",
                value: "image",
                systemImage: "photo.on.rectangle",
                controller: controller,
            ),
        ]

        let outputActions: [UIAction] = [
            makeModalitiesAction(
                title: "Add modalities: text",
                key: "output_modalities",
                value: "text",
                systemImage: "text.bubble",
                controller: controller,
            ),
            makeModalitiesAction(
                title: "Add modalities: image",
                key: "output_modalities",
                value: "image",
                systemImage: "photo.on.rectangle",
                controller: controller,
            ),
        ]

        let inputMenu = UIMenu(
            title: String(localized: "Input"),
            options: [.displayInline],
            children: inputActions,
        )

        let outputMenu = UIMenu(
            title: String(localized: "Output"),
            options: [.displayInline],
            children: outputActions,
        )

        return UIMenu(
            title: String(localized: "Modalities"),
            image: UIImage(systemName: "rectangle.stack.badge.play"),
            children: [inputMenu, outputMenu],
        )
    }

    private func buildProviderMenu(controller: JsonEditorController) -> UIMenu {
        let actions: [UIAction] = [
            makeDictionaryAction(
                title: "Set \("data_collection") to \("deny")",
                systemImage: "hand.raised.fill",
                controller: controller,
            ) { dictionary in
                var provider = dictionary["provider"] as? [String: Any] ?? [:]
                provider["data_collection"] = "deny"
                dictionary["provider"] = provider
            },
            makeDictionaryAction(
                title: "Set \("zdr") to \("true")",
                systemImage: "hand.raised.fill",
                controller: controller,
            ) { dictionary in
                var provider = dictionary["provider"] as? [String: Any] ?? [:]
                provider["zdr"] = true
                dictionary["provider"] = provider
            },
            makeDictionaryAction(
                title: "Add \("order")",
                systemImage: "list.number",
                controller: controller,
            ) { dictionary in
                dictionary["order"] = []
            },
        ]

        return UIMenu(
            title: String(localized: "Provider Options"),
            image: UIImage(systemName: "server.rack"),
            children: actions,
        )
    }

    private func makeDictionaryAction(
        title: String.LocalizationValue,
        systemImage: String,
        controller: JsonEditorController,
        update: @escaping (inout [String: Any]) -> Void,
    ) -> UIAction {
        UIAction(title: String(localized: title), image: UIImage(systemName: systemImage)) { _ in
            controller.updateValue(update)
        }
    }

    private func makeModalitiesAction(
        title: String.LocalizationValue,
        key: String,
        value: String,
        systemImage: String,
        controller: JsonEditorController,
    ) -> UIAction {
        UIAction(title: String(localized: title), image: UIImage(systemName: systemImage)) { _ in
            controller.updateValue {
                var values = $0[key] as? [String] ?? []
                values.append(value)
                $0[key] = Array(Set(values)).sorted()
            }
        }
    }
}

import AlertController
import ConfigurableKit
import Foundation
import Storage
import UIKit

extension CloudModelEditorController {
    func renderContent() {
        let model = ModelManager.shared.cloudModel(identifier: identifier)
        renderCommentSection(model)
        renderMetadataSection(model)
        renderCapabilitiesSection(model)
        renderParametersSection(model)
        renderNetworkingSection(model)
        renderFooterSection()
    }
}

private extension CloudModelEditorController {
    var notConfiguredText: String {
        String(localized: "Not Configured")
    }

    var notAvailableText: String {
        "N/A"
    }

    var configuredText: String {
        String(localized: "Configured")
    }

    func addSeparator() {
        stackView.addArrangedSubview(SeparatorView())
    }

    func addFooter(
        _ footer: ConfigurableSectionFooterView,
        adjust: ((inout UIEdgeInsets) -> Void)? = nil,
    ) {
        stackView.addArrangedSubviewWithMargin(footer) { insets in
            adjust?(&insets)
        }
    }

    func renderCommentSection(_ model: CloudModel?) {
        guard let comment = model?.comment, !comment.isEmpty else { return }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "Comment"),
        ) { $0.bottom /= 2 }
        addSeparator()

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(rawFooter: comment),
        )
        addSeparator()
    }

    func renderMetadataSection(_ model: CloudModel?) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "Metadata"),
        ) { $0.bottom /= 2 }
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeEndpointView(model: model))
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeTokenView(model: model))
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeModelIdentifierView(model: model))
        addSeparator()

        addFooter(
            ConfigurableSectionFooterView()
                .with(footer: "The endpoint needs to be written in full path to work. The path is usually /v1/chat/completions."),
        ) {
            $0.top /= 2
            $0.bottom = 0
        }
        addFooter(
            ConfigurableSectionFooterView()
                .with(footer: "After setting up, click the model identifier to edit it or retrieve a list from the server."),
        ) { $0.top /= 2 }
        addSeparator()
    }

    func renderCapabilitiesSection(_ model: CloudModel?) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "Capabilities"),
        ) { $0.bottom /= 2 }
        addSeparator()

        for capability in ModelCapabilities.allCases {
            let view = ConfigurableToggleActionView()
            view.boolValue = model?.capabilities.contains(capability) ?? false
            view.actionBlock = { [weak self] value in
                guard let self else { return }
                ModelManager.shared.editCloudModel(identifier: identifier) { editable in
                    var capabilities = editable.capabilities
                    if value {
                        capabilities.insert(capability)
                    } else {
                        capabilities.remove(capability)
                    }
                    editable.assign(\.capabilities, to: capabilities)
                }
            }
            view.configure(icon: .init(systemName: capability.icon))
            view.configure(title: capability.title)
            view.configure(description: capability.description)
            stackView.addArrangedSubviewWithMargin(view)
            addSeparator()
        }

        addFooter(
            ConfigurableSectionFooterView().with(
                footer: "We cannot determine whether this model includes additional capabilities. However, if supported, features such as visual recognition can be enabled manually here. Please note that if the model does not actually support these capabilities, attempting to enable them may result in errors.",
            ),
        ) { $0.top /= 2 }
        addSeparator()
    }

    func renderParametersSection(_ model: CloudModel?) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "Parameters"),
        ) { $0.bottom /= 2 }
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeNameView(model: model))
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeContextView(model: model))
        addSeparator()

        addFooter(
            ConfigurableSectionFooterView().with(
                footer: "We cannot determine the context length supported by the model. Please choose the correct configuration here. Configuring a context length smaller than the capacity can save costs. A context that is too long may be truncated during inference.",
            ),
        ) { $0.top /= 2 }
        addSeparator()
    }

    func renderNetworkingSection(_ model: CloudModel?) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: "Networking (Advanced)"),
        ) { $0.bottom /= 2 }
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeHeaderEditorView(model: model))
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeBodyFieldsView(model: model))
        addSeparator()

        stackView.addArrangedSubviewWithMargin(makeResponseFormatView(model: model))
        addSeparator()

        addFooter(
            ConfigurableSectionFooterView().with(
                footer: "Extra headers and body fields can be used to fine-tune model behavior and performance, such as enabling reasoning or setting reasoning budgets. The specific parameters vary across different service providers—please refer to their official documentation.",
            ),
        ) { $0.top /= 2 }
        addSeparator()
    }

    func renderFooterSection() {
        stackView.addArrangedSubviewWithMargin(UIView())

        let icon = UIImageView().with {
            $0.image = .modelCloud
            $0.tintColor = .separator
            $0.contentMode = .scaleAspectFit
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(24)
            }
        }
        stackView.addArrangedSubviewWithMargin(icon) { $0.bottom /= 2 }

        let footer = UILabel().with {
            $0.font = .rounded(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                weight: .regular,
            )
            $0.textColor = .label.withAlphaComponent(0.25)
            $0.numberOfLines = 0
            $0.text = identifier
            $0.textAlignment = .center
        }
        stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    func makeEndpointView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "link"))
        view.configure(title: "Inference Endpoint")
        view.configure(description: "This endpoint is used to send inference requests.")

        let endpoint = model?.endpoint ?? ""
        view.configure(value: endpoint.isEmpty ? notConfiguredText : endpoint)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return buildEndpointMenu(for: identifier, view: view)
        }
        return view
    }

    func makeTokenView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView().setTapBlock { [weak self] view in
            guard let self,
                  let currentModel = ModelManager.shared.cloudModel(identifier: identifier)
            else { return }

            let oldToken = currentModel.token
            let input = AlertInputViewController(
                title: "Edit Authorization (Optional)",
                message: "This token is sent as a Bearer credential in the Authorization header. Leave it blank if the endpoint does not require authentication.",
                placeholder: "Bearer token",
                text: currentModel.token,
            ) { [weak self] newToken in
                guard let self else { return }
                ModelManager.shared.editCloudModel(identifier: currentModel.id) {
                    $0.update(\.token, to: newToken)
                }
                view.configure(value: newToken.isEmpty ? notAvailableText : configuredText)

                let affectedModels = ModelManager.shared.cloudModels.value.filter {
                    $0.endpoint == currentModel.endpoint && $0.token == oldToken && $0.id != currentModel.id
                }

                guard !affectedModels.isEmpty else { return }
                let alert = AlertViewController(
                    title: "Update All Models",
                    message: "Would you like to apply the new Authorization token to all models with the same inference endpoint and current token?",
                ) { context in
                    context.addAction(title: "Cancel") { context.dispose() }
                    context.addAction(title: "Update All", attribute: .accent) {
                        context.dispose {
                            for item in affectedModels {
                                ModelManager.shared.editCloudModel(identifier: item.id) {
                                    $0.update(\.token, to: newToken)
                                }
                            }
                        }
                    }
                }
                view.parentViewController?.present(alert, animated: true)
            }
            view.parentViewController?.present(input, animated: true)
        }

        view.configure(icon: .init(systemName: "key.horizontal"))
        view.configure(title: "Authorization (Optional)")
        view.configure(description: "This token is sent as a Bearer credential in the Authorization header.")
        let value = (model?.token.isEmpty ?? true) ? notAvailableText : configuredText
        view.configure(value: value)
        return view
    }

    func makeModelIdentifierView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "circle"))
        view.configure(title: "Model Identifier")
        view.configure(description: "The name of the model to be used.")

        let modelIdentifier = model?.model_identifier ?? ""
        view.configure(value: modelIdentifier.isEmpty ? notConfiguredText : modelIdentifier)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return buildModelIdentifierMenu(for: identifier, view: view)
        }
        return view
    }

    func makeNameView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView().setTapBlock { [weak self] view in
            guard let self,
                  let currentModel = ModelManager.shared.cloudModel(identifier: identifier)
            else { return }
            let input = AlertInputViewController(
                title: "Edit Model Name",
                message: "Custom display name for this model.",
                placeholder: "Nickname (Optional)",
                text: currentModel.name,
            ) { [weak self] output in
                guard let self else { return }
                ModelManager.shared.editCloudModel(identifier: currentModel.id) {
                    $0.update(\.name, to: output)
                }
                view.configure(value: output.isEmpty ? notConfiguredText : output)
            }
            view.parentViewController?.present(input, animated: true)
        }

        view.configure(icon: .init(systemName: "tag"))
        view.configure(title: "Nickname")
        view.configure(description: "Custom display name for this model.")
        view.configure(value: (model?.name ?? "").isEmpty ? notConfiguredText : (model?.name ?? ""))
        return view
    }

    func makeContextView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.configure(icon: .init(systemName: "list.bullet"))
        view.configure(title: "Context")
        view.configure(description: "The context length for inference refers to the amount of information the model can retain and process at a given time. This context serves as the model’s memory, allowing it to understand and generate responses based on prior input.")

        let contextValue = model?.context.title ?? notConfiguredText
        view.configure(value: contextValue)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            return ModelContextLength.allCases.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.icon),
                ) { _ in
                    ModelManager.shared.editCloudModel(identifier: self.identifier) {
                        $0.update(\.context, to: item)
                    }
                    view.configure(value: item.title)
                }
            }
        }
        return view
    }

    func makeHeaderEditorView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView().setTapBlock { [weak self] view in
            guard let self,
                  let currentModel = ModelManager.shared.cloudModel(identifier: identifier)
            else { return }

            let jsonData = try? JSONSerialization.data(
                withJSONObject: currentModel.headers,
                options: [.prettyPrinted, .sortedKeys],
            )
            var text = String(data: jsonData ?? Data(), encoding: .utf8) ?? ""
            if text.isEmpty { text = "{}" }

            let editor = JsonStringMapEditorController(text: text)
            editor.title = String(localized: "Edit Header")
            editor.collectEditedContent { [weak self] result in
                guard let self else { return }
                guard
                    let data = result.data(using: .utf8),
                    let object = try? JSONDecoder().decode([String: String].self, from: data)
                else { return }

                ModelManager.shared.editCloudModel(identifier: currentModel.id) {
                    $0.update(\.headers, to: object)
                }
                view.configure(value: object.isEmpty ? notAvailableText : configuredText)
            }
            view.parentViewController?.navigationController?.pushViewController(editor, animated: true)
        }

        view.configure(icon: .init(systemName: "pencil"))
        view.configure(title: "Header")
        view.configure(description: "This value will be added to the request as additional header.")
        view.configure(
            value: (model?.headers.isEmpty ?? true) ? notAvailableText : configuredText,
        )
        return view
    }

    func makeBodyFieldsView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        view.setTapBlock { [weak self] view in
            guard let self,
                  let currentModel = ModelManager.shared.cloudModel(identifier: identifier)
            else { return }

            var text = currentModel.bodyFields
            if text.isEmpty {
                text = "{}"
            } else if let formatted = Self.prettyPrintedJson(from: text) {
                text = formatted
            }

            let editor = JsonEditorController(text: text)
            editor.secondaryMenuBuilder = { controller in
                self.buildExtraBodyEditorMenu(controller: controller)
            }

            editor.onTextDidChange = { draft in
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                let displayValue = (trimmed.isEmpty || Self.isEmptyJsonObject(draft))
                    ? self.notAvailableText
                    : self.configuredText
                view.configure(value: displayValue)
            }

            editor.title = String(localized: "Edit Fields")
            editor.collectEditedContent { result in
                guard
                    let data = result.data(using: .utf8),
                    (try? JSONSerialization.jsonObject(with: data)) != nil
                else { return }

                let normalized: String = if Self.isEmptyJsonObject(result) {
                    ""
                } else if let formatted = Self.prettyPrintedJson(from: result) {
                    formatted
                } else {
                    result
                }

                ModelManager.shared.editCloudModel(identifier: currentModel.id) { editable in
                    editable.update(\.bodyFields, to: normalized)
                }
                view.configure(value: normalized.isEmpty ? self.notAvailableText : self.configuredText)
            }

            view.parentViewController?.navigationController?.pushViewController(editor, animated: true)
        }

        view.configure(icon: .init(systemName: "pencil"))
        view.configure(title: "Body Fields")
        view.configure(description: "Configure inference-specific body fields here. The json key-value pairs you enter are merged into every request.")

        let hasBodyFields = !(model?.bodyFields.isEmpty ?? true) && !Self.isEmptyJsonObject(model?.bodyFields ?? "")
        view.configure(value: hasBodyFields ? configuredText : notAvailableText)
        return view
    }

    func makeResponseFormatView(model: CloudModel?) -> ConfigurableInfoView {
        let view = ConfigurableInfoView()
        responseFormatInfoView = view

        view.configure(icon: .init(systemName: "arrow.triangle.2.circlepath"))
        view.configure(title: "Content Format")
        view.configure(description: "Select which format this model should use when performing network requests.")

        let currentFormat = model?.response_format ?? .default
        view.configure(value: currentFormat.localizedTitle)
        view.use { [weak self, weak view] in
            guard let self, let view else { return [] }
            let selected = ModelManager.shared.responseFormat(for: identifier)
            return CloudModel.ResponseFormat.allCases.map { format in
                UIAction(
                    title: format.localizedTitle,
                    state: format == selected ? .on : .off,
                ) { [weak self] _ in
                    guard let self else { return }
                    ModelManager.shared.updateResponseFormat(for: identifier, to: format)
                    view.configure(value: format.localizedTitle)
                }
            }
        }
        return view
    }
}

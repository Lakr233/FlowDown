//
//  CloudModelEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/26/25.
//

import AlertController
import Combine
import ConfigurableKit
import Foundation
import OAuthKit
import Storage
import UIKit

class CloudModelEditorController: StackScrollController {
    let identifier: CloudModel.ID

    init(identifier: CloudModel.ID) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Edit Model")
    }

    #if targetEnvironment(macCatalyst)
        var documentPickerExportTempItems: [URL] = []
    #endif

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    var cancellables: Set<AnyCancellable> = .init()

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        navigationItem.rightBarButtonItem = .init(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped)
        )

        ModelManager.shared.cloudModels
            .removeDuplicates()
            .ensureMainThread()
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] values in
                guard let self, isVisible else { return }
                guard !values.contains(where: { $0.id == self.identifier }) else { return }
                navigationController?.popViewController(animated: true)
            }
            .store(in: &cancellables)
    }

    @objc func checkTapped() {
        navigationController?.popViewController()
    }

    override func setupContentViews() {
        super.setupContentViews()

        let model = ModelManager.shared.cloudModel(identifier: identifier)

        if let comment = model?.comment, !comment.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView()
                    .with(header: "Comment")
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView()
                    .with(rawFooter: comment)
            )
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Metadata")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let endpointView = ConfigurableInfoView()
        endpointView.configure(icon: .init(systemName: "link"))
        endpointView.configure(title: "Inference Endpoint")
        endpointView.configure(description: "This endpoint is used to send inference requests.")
        var endpoint = model?.endpoint ?? ""
        if endpoint.isEmpty { endpoint = String(localized: "Not Configured") }
        endpointView.configure(value: endpoint)
        endpointView.use { [weak self] in
            guard let self else { return [] }
            return buildEndpointMenu(for: identifier, view: endpointView)
        }
        stackView.addArrangedSubviewWithMargin(endpointView)
        stackView.addArrangedSubview(SeparatorView())

        let tokenView = ConfigurableInfoView().setTapBlock { view in
            guard let model = ModelManager.shared.cloudModel(identifier: model?.id) else { return }
            let oldToken = model.token
            let input = AlertInputViewController(
                title: "Edit Workgroup (Optional)",
                message: "This value will be added to the request to distinguish the workgroup on the remote. This part is optional, if not used, leave it blank.",
                placeholder: "workgroup-xxx",
                text: model.token
            ) { newToken in
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.token, to: newToken)
                }
                view.configure(value: newToken.isEmpty ? String(localized: "N/A") : String(localized: "Configured"))
                let list = ModelManager.shared.cloudModels.value.filter {
                    $0.endpoint == model.endpoint && $0.token == oldToken && $0.id != model.id
                }
                if !list.isEmpty {
                    let alert = AlertViewController(
                        title: "Update All Models",
                        message: "Would you like to apply the new workgroup to all? This requires the inference endpoint and the old workgroup equal to the current editing."
                    ) { context in
                        context.addAction(title: "Cancel") {
                            context.dispose()
                        }
                        context.addAction(title: "Update All", attribute: .accent) {
                            context.dispose {
                                for item in list {
                                    ModelManager.shared.editCloudModel(identifier: item.id) {
                                        $0.update(\.token, to: newToken)
                                    }
                                }
                            }
                        }
                    }
                    view.parentViewController?.present(alert, animated: true)
                }
            }
            view.parentViewController?.present(input, animated: true)
        }
        tokenView.configure(icon: .init(systemName: "square"))
        tokenView.configure(title: "Workgroup (Optional)")
        tokenView.configure(description: "This value will be added to the request to distinguish the workgroup on the remote.")
        tokenView.configure(
            value: (model?.token.isEmpty ?? true)
                ? String(localized: "N/A")
                : String(localized: "Configured")
        )

        stackView.addArrangedSubviewWithMargin(tokenView)
        stackView.addArrangedSubview(SeparatorView())

        let modelIdentifierView = ConfigurableInfoView()
        modelIdentifierView.configure(icon: .init(systemName: "circle"))
        modelIdentifierView.configure(title: "Model Identifier")
        modelIdentifierView.configure(description: "The name of the model to be used.")
        var modelIdentifier = model?.model_identifier ?? ""
        if modelIdentifier.isEmpty {
            modelIdentifier = String(localized: "Not Configured")
        }
        modelIdentifierView.configure(value: modelIdentifier)

        modelIdentifierView.use { [weak self] in
            guard let self else { return [] }
            return buildModelIdentifierMenu(for: identifier, view: modelIdentifierView)
        }
        stackView.addArrangedSubviewWithMargin(modelIdentifierView)
        stackView.addArrangedSubview(SeparatorView())

        // API Version
        let apiVersionView = ConfigurableInfoView().setTapBlock { view in
            guard let current = ModelManager.shared.cloudModel(identifier: model?.id) else { return }
            let input = AlertInputViewController(
                title: "Edit API Version",
                message: "Now only supports openai@v1.",
                placeholder: "openai@v1",
                text: ""
            ) { text in
                let lowered = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                view.configure(value: lowered)
                if lowered == "openai@v1" {
                    ModelManager.shared.editCloudModel(identifier: current.id) { $0.update(\.api_version, to: .oai_completion) }
                } else if lowered == "openai@oauth" {
                    print("You've got the hidden feature!")
                    ModelManager.shared.editCloudModel(identifier: current.id) { $0.update(\.api_version, to: .oai_response) }
                    // Set default endpoint and model identifier for OpenAI OAuth
                    ModelManager.shared.editCloudModel(identifier: current.id) {
                        $0.update(\.endpoint, to: "https://chatgpt.com/backend-api/codex/responses")
                        $0.update(\.model_identifier, to: "gpt-5")
                        $0.update(\.context, to: .long_100k)
                        $0.update(\.capabilities, to: [.visual, .tool])
                    }

                    // Begin OAuth flow
                    let oauthConfig = OAuthConfiguration(
                        clientId: "app_EMoamEEZ73f0CkXaXp7hrann",
                        authorizationEndpoint: URL(string: "https://auth.openai.com/oauth/authorize")!,
                        tokenEndpoint: URL(string: "https://auth.openai.com/oauth/token")!,
                        redirectURI: URL(string: "http://localhost:1455/auth/callback")!,
                        scope: "openid profile email offline_access",
                        additionalParameters: [
                            "id_token_add_organizations": "true",
                            "codex_cli_simplified_flow": "true",
                        ],
                        usePKCE: true,
                        pkceMethod: .sha256
                    )
                    let oauthClient = OAuthClient(configuration: oauthConfig)

                    let alert = AlertViewController(
                        title: "Start OAuth",
                        message: "We will open the authorization page in your browser. After login, copy the redirected URL and paste it back here."
                    ) { context in
                        context.addAction(title: "Cancel") { context.dispose() }
                        context.addAction(title: "Continue", attribute: .accent) {
                            context.dispose {
                                do {
                                    let url = try oauthClient.buildAuthorizationURL()
                                    UIApplication.shared.open(url)

                                    let paste = AlertInputViewController(
                                        title: "Paste Callback URL",
                                        message: "After completing login, paste the full callback URL here.",
                                        placeholder: "http://localhost:1455/auth/callback?code=...&state=...",
                                        text: ""
                                    ) { callback in
                                        guard let callbackURL = URL(string: callback),
                                              let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
                                              let items = components.queryItems
                                        else { return }

                                        var code: String?
                                        var state: String?
                                        for item in items {
                                            if item.name == "code" { code = item.value }
                                            if item.name == "state" { state = item.value }
                                            if item.name == "error" {
                                                Indicator.present(title: "OAuth Error: \(item.value ?? "Unknown Error")")
                                                return
                                            }
                                        }
                                        guard let code else { return }
                                        Task { @MainActor in
                                            do {
                                                _ = try await oauthClient.exchangeCodeForToken(code: code, state: state)
                                                let token = try await oauthClient.getValidToken()
                                                ModelManager.shared.editCloudModel(identifier: current.id) { $0.update(\.token, to: token.accessToken) }
                                                Indicator.present(title: "OAuth Complete")
                                            } catch {
                                                Indicator.present(title: "\(error.localizedDescription)")
                                            }
                                        }
                                    }
                                    self.present(paste, animated: true)
                                } catch {
                                    Indicator.present(title: "\(error.localizedDescription)")
                                }
                            }
                        }
                    }
                    view.parentViewController?.present(alert, animated: true)
                }
            }
            view.parentViewController?.present(input, animated: true)
        }
        apiVersionView.configure(icon: UIImage(systemName: "arrow.triangle.2.circlepath"))
        apiVersionView.configure(title: "API Version")
        apiVersionView.configure(description: "Choose the API protocol for this model.")
        let apiValue = switch model?.api_version ?? .oai_completion {
        case .oai_completion: "openai@v1"
        case .oai_response: "OpenAI OAuth"
        case .claude: "Claude"
        }
        apiVersionView.configure(value: apiValue)
        stackView.addArrangedSubviewWithMargin(apiVersionView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "The endpoint needs to be written in full path to work. The path is usually /v1/chat/completions.")
        ) {
            $0.top /= 2
            $0.bottom = 0
        }
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "After setting up, click the model identifier to edit it or retrieve a list from the server.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Networking (Optional)")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        // additional header
        let headerEditorView = ConfigurableInfoView().setTapBlock { view in
            guard let model = ModelManager.shared.cloudModel(identifier: model?.id) else { return }
            let jsonData = try? JSONSerialization.data(withJSONObject: model.headers, options: .prettyPrinted)
            var text = String(data: jsonData ?? Data(), encoding: .utf8) ?? ""
            if text.isEmpty { text = "{}" }
            let textEditor = JsonStringMapEditorController(text: text)
            textEditor.title = String(localized: "Edit Additional Header")
            textEditor.collectEditedContent { result in
                guard let object = try? JSONDecoder().decode([String: String].self, from: result.data(using: .utf8) ?? .init()) else {
                    return
                }
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.headers, to: object)
                }
                view.configure(value: object.isEmpty ? String(localized: "N/A") : String(localized: "Configured"))
            }
            view.parentViewController?.navigationController?.pushViewController(textEditor, animated: true)
        }
        headerEditorView.configure(icon: .init(systemName: "pencil"))
        headerEditorView.configure(title: "Additional Header")
        headerEditorView.configure(description: "This value will be added to the request as additional header.")
        headerEditorView.configure(value: model?.headers.isEmpty ?? true ? String(localized: "N/A") : String(localized: "Configured"))

        stackView.addArrangedSubviewWithMargin(headerEditorView)
        stackView.addArrangedSubview(SeparatorView())

        // additional body fields
        let bodyFieldsEditorView = ConfigurableInfoView()
        bodyFieldsEditorView.setTapBlock { [weak self] view in
            guard let model = ModelManager.shared.cloudModel(identifier: model?.id) else { return }
            var text = model.bodyFields
            if text.isEmpty { text = "{}" }

            let textEditor = JsonEditorController(text: text)
            textEditor.secondaryMenuBuilder = { controller in
                self?.buildExtraBodyEditorMenu(controller: controller) ?? .init()
            }

            textEditor.onTextDidChange = { draft in
                let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || Self.isEmptyJsonObject(draft) {
                    view.configure(value: String(localized: "N/A"))
                } else {
                    view.configure(value: String(localized: "Configured"))
                }
            }

            textEditor.title = String(localized: "Edit Additional Body Fields")
            textEditor.collectEditedContent { result in
                guard let data = result.data(using: .utf8),
                      (try? JSONSerialization.jsonObject(with: data)) != nil
                else {
                    return
                }
                let normalizedResult = Self.isEmptyJsonObject(result) ? "" : result
                ModelManager.shared.editCloudModel(identifier: model.id) { editable in
                    editable.update(\.bodyFields, to: normalizedResult)
                }
                view.configure(value: normalizedResult.isEmpty ? String(localized: "N/A") : String(localized: "Configured"))
            }

            view.parentViewController?.navigationController?.pushViewController(textEditor, animated: true)
        }
        bodyFieldsEditorView.configure(icon: .init(systemName: "pencil"))
        bodyFieldsEditorView.configure(title: "Additional Body Fields")
        bodyFieldsEditorView.configure(description: "Configure inference-specific body fields here. The JSON key-value pairs you enter are merged into every request.")
        let hasBodyFields = !(model?.bodyFields.isEmpty ?? true) && !Self.isEmptyJsonObject(model?.bodyFields ?? "")
        bodyFieldsEditorView.configure(value: hasBodyFields ? String(localized: "Configured") : String(localized: "N/A"))

        stackView.addArrangedSubviewWithMargin(bodyFieldsEditorView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "Extra headers and body fields can be used to fine-tune model behavior and performance, such as enabling reasoning or setting reasoning budgets. The specific parameters vary across different service providers—please refer to their official documentation.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Capabilities")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        for cap in ModelCapabilities.allCases {
            let view = ConfigurableToggleActionView()
            view.boolValue = model?.capabilities.contains(cap) ?? false
            view.actionBlock = { [weak self] value in
                guard let self else { return }
                ModelManager.shared.editCloudModel(identifier: identifier) { model in
                    var capabilities = model.capabilities
                    if value {
                        capabilities.insert(cap)
                    } else {
                        capabilities.remove(cap)
                    }
                    model.assign(\.capabilities, to: capabilities)
                }
            }
            view.configure(icon: .init(systemName: cap.icon))
            view.configure(title: cap.title)
            view.configure(description: cap.description)
            stackView.addArrangedSubviewWithMargin(view)
            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "We cannot determine whether this model includes additional capabilities. However, if supported, features such as visual recognition can be enabled manually here. Please note that if the model does not actually support these capabilities, attempting to enable them may result in errors.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Context")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let contextListViewAnnotation = ConfigurableInfoView()
        contextListViewAnnotation.configure(icon: .init(systemName: "list.bullet"))
        contextListViewAnnotation.configure(title: "Context Length")
        contextListViewAnnotation.configure(description: "The context length for inference refers to the amount of information the model can retain and process at a given time. This context serves as the model’s memory, allowing it to understand and generate responses based on prior input.")
        let value = model?.context.title ?? String(localized: "Not Configured")
        contextListViewAnnotation.configure(value: value)
        contextListViewAnnotation.use {
            ModelContextLength.allCases.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.icon)
                ) { _ in
                    ModelManager.shared.editCloudModel(identifier: model?.id) {
                        $0.update(\.context, to: item)
                    }
                    contextListViewAnnotation.configure(value: item.title)
                }
            }
        }
        stackView.addArrangedSubviewWithMargin(contextListViewAnnotation)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "We cannot determine the context length supported by the model. Please choose the correct configuration here. Configuring a context length smaller than the capacity can save costs. A context that is too long may be truncated during inference.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Parameters")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let nameView = ConfigurableInfoView().setTapBlock { view in
            guard let model = ModelManager.shared.cloudModel(identifier: model?.id) else { return }
            let input = AlertInputViewController(
                title: "Edit Model Name",
                message: "Custom display name for this model.",
                placeholder: "Nickname (Optional)",
                text: model.name
            ) { output in
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.name, to: output)
                }
                if output.isEmpty {
                    view.configure(value: String(localized: "Not Configured"))
                } else {
                    view.configure(value: output)
                }
            }
            view.parentViewController?.present(input, animated: true)
        }
        nameView.configure(icon: .init(systemName: "tag"))
        nameView.configure(title: "Nickname (Optional)")
        nameView.configure(description: "Custom display name for this model.")
        var nameValue = model?.name ?? ""
        if nameValue.isEmpty { nameValue = String(localized: "Not Configured") }
        nameView.configure(value: nameValue)
        stackView.addArrangedSubviewWithMargin(nameView)
        stackView.addArrangedSubview(SeparatorView())

        let temperatureView = ConfigurableInfoView()
        temperatureView.configure(icon: .init(systemName: "sparkles"))
        temperatureView.configure(title: "Imagination")
        temperatureView.configure(description: "This parameter can be used to control the personality of the model. The more imaginative, the more unstable the output. This parameter is also known as temperature.")
        let temperatureDisplay = ModelManager.shared.displayTextForTemperature(
            preference: model?.temperature_preference ?? .inherit,
            override: model?.temperature_override
        )
        temperatureView.configure(value: temperatureDisplay)
        temperatureView.use { [weak self] in
            guard let self,
                  let model = ModelManager.shared.cloudModel(identifier: identifier)
            else { return [] }

            var actions: [UIMenuElement] = []

            let inheritAction = UIAction(
                title: String(localized: "Inference default"),
                image: UIImage(systemName: "circle.dashed")
            ) { _ in
                ModelManager.shared.editCloudModel(identifier: model.id) { item in
                    item.update(\.temperature_preference, to: .inherit)
                    item.update(\.temperature_override, to: nil)
                }
                temperatureView.configure(value: ModelManager.shared.displayTextForTemperature(
                    preference: .inherit,
                    override: nil
                ))
            }
            inheritAction.state = model.temperature_preference == .inherit ? .on : .off
            actions.append(inheritAction)

            for preset in ModelManager.shared.temperaturePresets {
                let action = UIAction(
                    title: preset.title,
                    image: UIImage(systemName: preset.icon)
                ) { _ in
                    ModelManager.shared.editCloudModel(identifier: model.id) { item in
                        item.update(\.temperature_preference, to: .custom)
                        item.update(\.temperature_override, to: preset.value)
                    }
                    temperatureView.configure(value: ModelManager.shared.displayTextForTemperature(
                        preference: .custom,
                        override: preset.value
                    ))
                }
                if model.temperature_preference == .custom,
                   let value = model.temperature_override,
                   abs(value - preset.value) < 0.0001
                {
                    action.state = .on
                }
                actions.append(action)
            }

            return actions
        }
        stackView.addArrangedSubviewWithMargin(temperatureView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Verification")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let verifyButton = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            guard let model = ModelManager.shared.cloudModel(identifier: identifier) else { return }
            Indicator.progress(
                title: "Verifying Model",
                controller: self
            ) { completionHandler in
                let result = await withCheckedContinuation { continuation in
                    ModelManager.shared.testCloudModel(model) { result in
                        continuation.resume(returning: result)
                    }
                }
                try result.get()
                await completionHandler {
                    Indicator.present(
                        title: "Model Verified",
                        referencingView: self.view
                    )
                }
            }
        }
        verifyButton.configure(icon: UIImage(systemName: "testtube.2"))
        verifyButton.configure(title: "Verify Model")
        verifyButton.configure(description: "Verify the model by sending a test request.")
        stackView.addArrangedSubviewWithMargin(verifyButton)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "Verification process will send a standard inference request to the inference node and verify the returned status code. This process requires the server to return status code: 200. The verification process may incur standard charges from your service provider.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Shortcuts")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let exportOption = ConfigurableActionView { @MainActor [weak self] controller in
            guard let self,
                  let model = ModelManager.shared.cloudModel(identifier: identifier)
            else { return }
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            guard let data = try? encoder.encode(model) else { return }
            let fileName = "Export-\(model.modelDisplayName.sanitizedFileName)\(model.auxiliaryIdentifier)"
            DisposableExporter(
                data: data,
                name: fileName,
                pathExtension: ModelManager.flowdownModelConfigurationExtension,
                title: "Export Model"
            ).run(anchor: controller.view)
        }
        exportOption.configure(icon: UIImage(systemName: "square.and.arrow.up"))
        exportOption.configure(title: "Export Model")
        exportOption.configure(description: "Export this model to share with others.")
        stackView.addArrangedSubviewWithMargin(exportOption)
        stackView.addArrangedSubview(SeparatorView())

        let duplicateModel = ConfigurableActionView { @MainActor [weak self] _ in
            guard let nav = self?.navigationController else { return }
            let newIdentifier = UUID().uuidString
            ModelManager.shared.editCloudModel(identifier: self?.identifier) {
                $0.update(\.objectId, to: newIdentifier)
                $0.update(\.model_identifier, to: "")
                $0.update(\.creation, to: $0.modified)
            }
            guard let newModel = ModelManager.shared.cloudModel(identifier: newIdentifier) else { return }
            assert(newModel.objectId == newIdentifier)
            nav.popViewController(animated: true) {
                let editor = CloudModelEditorController(identifier: newModel.id)
                nav.pushViewController(editor, animated: true)
            }
        }
        duplicateModel.configure(icon: UIImage(systemName: "doc.on.doc"))
        duplicateModel.configure(title: "Duplicate")
        duplicateModel.configure(description: "Create a new model by copying the current configuration.")
        stackView.addArrangedSubviewWithMargin(duplicateModel)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "After creating a copy, you can choose a new model. This is useful if the endpoint provides multiple models.")
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Management")
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())
        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            deleteModel()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: "Delete Model")
        deleteAction.configure(description: "Delete this model from your device.")
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

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
                weight: .regular
            )
            $0.textColor = .label.withAlphaComponent(0.25)
            $0.numberOfLines = 0
            $0.text = identifier
            $0.textAlignment = .center
        }
        stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    @objc func deleteModel() {
        let alert = AlertViewController(
            title: "Delete Model",
            message: "Are you sure you want to delete this model? This action cannot be undone."
        ) { context in
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Delete", attribute: .accent) {
                context.dispose { [weak self] in
                    guard let self else { return }
                    ModelManager.shared.removeCloudModel(identifier: identifier)
                    navigationController?.popViewController(animated: true)
                }
            }
        }
        present(alert, animated: true)
    }

    // MARK: - Menu Builders

    private func buildEndpointMenu(for modelId: CloudModel.ID, view: ConfigurableInfoView) -> [UIMenuElement] {
        guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return [] }

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { _ in
            guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return }
            let input = AlertInputViewController(
                title: "Edit Endpoint",
                message: "This endpoint is used to send inference requests.",
                placeholder: "https://",
                text: model.endpoint.isEmpty ? "https://" : model.endpoint
            ) { output in
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.endpoint, to: output)
                }
                view.configure(value: output.isEmpty ? String(localized: "Not Configured") : output)
            }
            view.parentViewController?.present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        // Add copy action if there's a value
        if !model.endpoint.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = model.endpoint
            }
            menuElements.append(copyAction)
        }

        // Get unique endpoints from existing models
        let existingEndpoints = Set(ModelManager.shared.cloudModels.value.compactMap { model in
            model.endpoint.isEmpty ? nil : model.endpoint
        }).sorted()

        if !existingEndpoints.isEmpty {
            let selectActions = existingEndpoints.map { endpoint in
                UIAction(title: endpoint) { _ in
                    ModelManager.shared.editCloudModel(identifier: modelId) {
                        $0.update(\.endpoint, to: endpoint)
                    }
                    view.configure(value: endpoint)
                }
            }

            menuElements.append(UIMenu(
                title: String(localized: "Select from Existing"),
                image: UIImage(systemName: "list.bullet"),
                options: [.displayInline],
                children: selectActions
            ))
        }

        return menuElements
    }

    private func buildModelIdentifierMenu(for modelId: CloudModel.ID, view: ConfigurableInfoView) -> [UIMenuElement] {
        guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return [] }

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam")
        ) { _ in
            guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return }
            let input = AlertInputViewController(
                title: "Edit Model Identifier",
                message: "The name of the model to be used.",
                placeholder: "Model Identifier",
                text: model.model_identifier
            ) { output in
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.model_identifier, to: output)
                }
                if output.isEmpty {
                    view.configure(value: String(localized: "Not Configured"))
                } else {
                    view.configure(value: output)
                }
            }
            view.parentViewController?.present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        // Add copy action if there's a value
        if !model.model_identifier.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = model.model_identifier
            }
            menuElements.append(copyAction)
        }

        if model.api_version == .oai_response {
            // OpenAI OAuth: provide fixed options and do not fetch from server
            let options = ["gpt-5-codex", "gpt-5"]
            let actions = options.map { option in
                UIAction(title: option, state: model.model_identifier == option ? .on : .off) { _ in
                    ModelManager.shared.editCloudModel(identifier: model.id) { editable in
                        editable.update(\.model_identifier, to: option)
                    }
                    view.configure(value: option)
                }
            }
            menuElements.append(UIMenu(
                title: String(localized: "Select Model supported by codex"),
                image: UIImage(systemName: "rectangle.3.group"),
                options: [.displayInline],
                children: actions
            ))
        } else {
            let deferredElement = UIDeferredMenuElement.uncached { completion in
                guard let model = ModelManager.shared.cloudModel(identifier: modelId) else {
                    completion([])
                    return
                }

                ModelManager.shared.fetchModelList(identifier: model.id) { list in
                    if list.isEmpty {
                        completion([UIAction(
                            title: String(localized: "(None)"),
                            attributes: .disabled
                        ) { _ in }])
                        return
                    }
                    let menuElements = self.buildModelSelectionMenu(from: list) { selection in
                        ModelManager.shared.editCloudModel(identifier: model.id) {
                            $0.update(\.model_identifier, to: selection)
                        }
                        view.configure(value: selection)
                    }
                    completion(menuElements)
                }
            }

            menuElements.append(UIMenu(
                title: String(localized: "Select from Server"),
                image: UIImage(systemName: "icloud.and.arrow.down"),
                children: [deferredElement]
            ))
        }

        return menuElements
    }

    private func buildModelSelectionMenu(
        from list: [String],
        selectionHandler: @escaping (String) -> Void
    ) -> [UIMenuElement] {
        var buildSections: [String: [(String, String)]] = [:]
        for item in list {
            var scope = ""
            var trimmedName = item
            if item.contains("/") {
                scope = item.components(separatedBy: "/").first ?? ""
                trimmedName = trimmedName.replacingOccurrences(of: scope + "/", with: "")
            }
            buildSections[scope, default: []].append((trimmedName, item))
        }

        var children: [UIMenuElement] = []
        var options: UIMenu.Options = []
        if list.count < 10 { options.insert(.displayInline) }

        for key in buildSections.keys.sorted() {
            let items = buildSections[key] ?? []
            guard !items.isEmpty else { continue }
            let key = key.isEmpty ? String(localized: "Ungrouped") : key
            children.append(UIMenu(
                title: key,
                image: UIImage(systemName: "folder"),
                options: options,
                children: items.map { item in
                    UIAction(title: item.0) { _ in
                        selectionHandler(item.1)
                    }
                }
            ))
        }

        return children
    }

    /// Check if a JSON string represents an empty object (e.g., "{}", "{ }", "{  \n  }")
    private static func isEmptyJsonObject(_ jsonString: String) -> Bool {
        guard let data = jsonString.data(using: .utf8),
              let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return jsonObject.isEmpty
    }
}

private extension CloudModelEditorController {
    enum ReasoningParametersType: String, CaseIterable {
        // https://github.com/langchain-ai/langchain-nvidia/blob/main/libs/ai-endpoints/tests/unit_tests/test_chat_models.py
        case reasoning // openrouter
        case enableThinking = "enable_thinking"
        case thinkingMode = "thinking_mode" // llama

        var title: String.LocalizationValue { "Use \(rawValue) Key" }

        func insert(to dic: inout [String: Any]) {
            switch self {
            case .enableThinking: dic[rawValue] = true
            case .thinkingMode: dic[rawValue] = ["type": "enabled"]
            case .reasoning: dic[rawValue] = ["enabled": true]
            }
        }
    }

    enum ReasoningEffort: String, CaseIterable {
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

        var title: String.LocalizationValue {
            "Set Budget to \(thinkingBudgetTokens) Tokens"
        }
    }

    private func buildExtraBodyEditorMenu(controller: JsonEditorController) -> UIMenu {
        .init(children: [UIDeferredMenuElement.uncached { comp in
            var children: [UIMenuElement] = []
            let reasoningParmsActions = ReasoningParametersType.allCases.map { type -> UIAction in
                UIAction(title: String(localized: type.title), image: UIImage(systemName: "key")) { _ in
                    let dic = controller.currentDictionary
                    let existingReasoningKeys = ReasoningParametersType.allCases.filter { existingType in
                        dic.keys.contains(existingType.rawValue)
                    }
                    if !existingReasoningKeys.isEmpty, existingReasoningKeys != [type] {
                        let alert = AlertViewController(
                            title: "Duplicated Content",
                            message: "Another key already exists, which usually causes errors. You can choose to replace it."
                        ) { context in
                            context.addAction(title: "Cancel") { context.dispose() }
                            context.addAction(title: "Replace", attribute: .accent) {
                                context.dispose {
                                    controller.updateValue {
                                        for type in existingReasoningKeys {
                                            $0.removeValue(forKey: type.rawValue)
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
            children.append(UIMenu(
                title: String(localized: "Reasoning Parameters"),
                image: UIImage(systemName: "brain.head.profile"),
                options: [.displayInline],
                children: reasoningParmsActions
            ))

            let dic = controller.currentDictionary
            let existingReasoningKeys = ReasoningParametersType.allCases.filter { existingType in
                dic.keys.contains(existingType.rawValue)
            }
            if existingReasoningKeys.count == 1, let key = existingReasoningKeys.first {
                children.append(UIMenu(
                    title: String(localized: "Reasoning Budget"),
                    image: UIImage(systemName: "gauge"),
                    options: [.displayInline],
                    children: ReasoningEffort.allCases.map { effort -> UIAction in
                        UIAction(title: String(localized: effort.title)) { _ in
                            controller.updateValue { dic in
                                switch key {
                                case .thinkingMode:
                                    dic["thinking_budget"] = effort.thinkingBudgetTokens
                                case .enableThinking:
                                    dic["thinking_budget"] = effort.thinkingBudgetTokens
                                case .reasoning:
                                    var value = dic[key.rawValue, default: [:]] as? [String: Any] ?? [:]
                                    value["max_tokens"] = effort.thinkingBudgetTokens
                                    dic[key.rawValue] = value
                                }
                            }
                        }
                    }
                ))
            } else {
                let title: String.LocalizationValue = existingReasoningKeys.isEmpty
                    ? "Unavailable - No Reasoning Key"
                    : "Unavailable - Multiple Reasoning Keys"
                children.append(UIMenu(
                    title: String(localized: "Reasoning Budget"),
                    image: UIImage(systemName: "gauge"),
                    options: [.displayInline],
                    children: [
                        UIAction(
                            title: String(localized: title),
                            image: UIImage(systemName: "xmark.circle"),
                            attributes: [.disabled]
                        ) { _ in },
                    ]
                ))
            }

            comp(children)
        }])
    }
}

#if targetEnvironment(macCatalyst)
    extension CloudModelEditorController: UIDocumentPickerDelegate {
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt _: [URL]) {
            for cleanableURL in documentPickerExportTempItems {
                try? FileManager.default.removeItem(at: cleanableURL)
            }
            documentPickerExportTempItems.removeAll()
        }
    }
#endif

import AlertController
import Foundation
import Storage
import UIKit

extension CloudModelEditorController {
    func buildActionsMenu() -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            completion(makeActionMenuElements())
        }
        return UIMenu(children: [deferred])
    }

    func makeActionMenuElements() -> [UIMenuElement] {
        SettingController.SettingContent.ModelController.makeActionMenuElements(
            for: identifier,
            controller: self,
            actionType: .cloud(
                verify: { [weak self] in await self?.runVerification() },
                evaluate: { [weak self] in EvaluationController.begin(controller: self, model: self?.identifier) },
                export: { [weak self] in self?.exportCurrentModel() },
                duplicate: { [weak self] in self?.duplicateCurrentModel() },
                delete: { [weak self] in self?.deleteModel() },
            ),
        )
    }

    @MainActor
    func runVerification() async {
        guard let model = ModelManager.shared.cloudModel(identifier: identifier) else { return }
        Indicator.progress(
            title: "Verifying Model",
            controller: self,
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
                    referencingView: self.view,
                )
            }
        }
    }

    @MainActor
    func exportCurrentModel() {
        guard let model = ModelManager.shared.cloudModel(identifier: identifier) else { return }
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml
        guard let data = try? encoder.encode(model) else { return }
        let fileName = "Export-\(model.modelDisplayName.sanitizedFileName)\(model.auxiliaryIdentifier)"
        DisposableExporter(
            data: data,
            name: fileName,
            pathExtension: ModelManager.flowdownModelConfigurationExtension,
            title: "Export Model",
        ).run(anchor: navigationController?.view ?? view)
    }

    @MainActor
    func duplicateCurrentModel() {
        guard let nav = navigationController else { return }
        let newIdentifier = UUID().uuidString
        ModelManager.shared.editCloudModel(identifier: identifier) {
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

    @MainActor
    @objc func deleteModel() {
        presentDeleteConfirmation(
            title: "Delete Model",
            message: "Are you sure you want to delete this model? This action cannot be undone.",
        ) { [weak self] in
            guard let self else { return }
            ModelManager.shared.removeCloudModel(identifier: identifier)
            navigationController?.popViewController(animated: true)
        }
    }

    func buildEndpointMenu(for modelId: CloudModel.ID, view: ConfigurableInfoView) -> [UIMenuElement] {
        guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return [] }

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam"),
        ) { [weak self, weak view] _ in
            guard let self,
                  let infoView = view,
                  let model = ModelManager.shared.cloudModel(identifier: modelId)
            else { return }
            let input = AlertInputViewController(
                title: "Edit Endpoint",
                message: "This endpoint is used to send inference requests.",
                placeholder: "\("https://")",
                text: model.endpoint.isEmpty ? "https://" : model.endpoint,
            ) { [weak self, weak infoView] output in
                guard let self, let infoView else { return }
                applyEndpoint(output, toModel: model.id, view: infoView)
            }
            infoView.parentViewController?.present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        if !model.endpoint.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { _ in
                UIPasteboard.general.string = model.endpoint
            }
            menuElements.append(copyAction)
        }

        let existingEndpoints = Set(ModelManager.shared.cloudModels.value.compactMap { model in
            model.endpoint.isEmpty ? nil : model.endpoint
        }).sorted()

        if !existingEndpoints.isEmpty {
            let selectActions = existingEndpoints.map { endpoint in
                UIAction(title: endpoint) { [weak self, weak view] _ in
                    guard let self, let infoView = view else { return }
                    applyEndpoint(endpoint, toModel: modelId, view: infoView)
                }
            }

            menuElements.append(UIMenu(
                title: String(localized: "Select from Existing"),
                image: UIImage(systemName: "list.bullet"),
                options: [.displayInline],
                children: selectActions,
            ))
        }

        return menuElements
    }

    func applyEndpoint(
        _ endpoint: String,
        toModel modelId: CloudModel.ID,
        view: ConfigurableInfoView,
    ) {
        let trimmed = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        ModelManager.shared.editCloudModel(identifier: modelId) { model in
            model.update(\.endpoint, to: trimmed)
        }

        let displayValue = trimmed.isEmpty ? String(localized: "Not Configured") : trimmed
        view.configure(value: displayValue)

        guard !trimmed.isEmpty else { return }

        guard let inferredFormat = CloudModel.ResponseFormat.inferredFormat(fromEndpoint: trimmed) else {
            presentEndpointFormatMismatchAlert()
            return
        }

        let currentFormat = ModelManager.shared.responseFormat(for: modelId)
        if currentFormat != inferredFormat {
            ModelManager.shared.updateResponseFormat(for: modelId, to: inferredFormat)
        }

        responseFormatInfoView?.configure(value: inferredFormat.localizedTitle)

        if let model = ModelManager.shared.cloudModel(identifier: modelId) {
            let defaultEndpoints = Set(CloudModel.ResponseFormat.allCases.map(\.defaultModelListEndpoint))
            if defaultEndpoints.contains(model.model_list_endpoint) {
                ModelManager.shared.editCloudModel(identifier: modelId) { editable in
                    editable.update(\.model_list_endpoint, to: inferredFormat.defaultModelListEndpoint)
                }
            }
        }
    }

    func presentEndpointFormatMismatchAlert() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let alert = AlertViewController(
                title: "Unable to Match Request Format",
                message: "This data has been saved, but we could not match a request format for this endpoint. This is usually a mistake. In most cases your request should end with /v1/chat/completions.",
            ) { context in
                context.addAction(title: "OK", attribute: .accent) {
                    context.dispose()
                }
            }
            if let presented = presentedViewController {
                presented.present(alert, animated: true)
            } else {
                present(alert, animated: true)
            }
        }
    }

    func buildModelIdentifierMenu(for modelId: CloudModel.ID, view: ConfigurableInfoView) -> [UIMenuElement] {
        guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return [] }

        let editAction = UIAction(
            title: String(localized: "Edit"),
            image: UIImage(systemName: "character.cursor.ibeam"),
        ) { _ in
            guard let model = ModelManager.shared.cloudModel(identifier: modelId) else { return }
            let input = AlertInputViewController(
                title: "Edit Model Identifier",
                message: "The name of the model to be used.",
                placeholder: "Model Identifier",
                text: model.model_identifier,
            ) { output in
                ModelManager.shared.editCloudModel(identifier: model.id) {
                    $0.update(\.model_identifier, to: output)
                }
                view.configure(value: output.isEmpty ? String(localized: "Not Configured") : output)
            }
            view.parentViewController?.present(input, animated: true)
        }

        var menuElements: [UIMenuElement] = [editAction]

        if !model.model_identifier.isEmpty {
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc"),
            ) { _ in
                UIPasteboard.general.string = model.model_identifier
            }
            menuElements.append(copyAction)
        }

        let deferredElement = UIDeferredMenuElement.uncached { [weak self, weak view] completion in
            guard let model = ModelManager.shared.cloudModel(identifier: modelId) else {
                completion([])
                return
            }

            ModelManager.shared.fetchModelList(identifier: model.id) { [weak self, weak view] list in
                guard let self else {
                    completion([])
                    return
                }
                guard !list.isEmpty else {
                    completion([UIAction(
                        title: String(localized: "(None)"),
                        attributes: .disabled,
                    ) { _ in }])
                    return
                }

                let menuElements = buildModelSelectionMenu(from: list) { selection in
                    ModelManager.shared.editCloudModel(identifier: model.id) {
                        $0.update(\.model_identifier, to: selection)
                    }
                    view?.configure(value: selection)
                }
                completion(menuElements)
            }
        }

        menuElements.append(UIMenu(
            title: String(localized: "Select from Server"),
            image: UIImage(systemName: "icloud.and.arrow.down"),
            children: [deferredElement],
        ))

        return menuElements
    }

    func buildModelSelectionMenu(
        from list: [String],
        selectionHandler: @escaping (String) -> Void,
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
                },
            ))
        }

        return children
    }
}

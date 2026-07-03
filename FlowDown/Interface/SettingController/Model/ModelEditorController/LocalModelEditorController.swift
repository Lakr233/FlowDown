//
//  LocalModelEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/26/25.
//

import AlertController
import Combine
import ConfigurableKit
import MLX
import Storage
import UIKit

extension ModelCapabilities {
    static var localModelEditable: [ModelCapabilities] = [
        .visual, // probably fixed
        .tool,
    ]
}

private let dateFormatter: DateFormatter = .init().with {
    $0.dateStyle = .short
    $0.timeStyle = .short
}

class LocalModelEditorController: StackScrollController {
    let identifier: LocalModel.ID
    init(identifier: LocalModel.ID) {
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

        let confirmItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped),
        )
        let actionsItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: nil,
            action: nil,
        )
        actionsItem.accessibilityLabel = String(localized: "More Actions")
        actionsItem.menu = buildActionsMenu()
        navigationItem.rightBarButtonItems = [confirmItem, actionsItem]

        ModelManager.shared.localModels
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

    private func buildActionsMenu() -> UIMenu {
        let deferred = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            completion(makeActionMenuElements())
        }
        return UIMenu(children: [deferred])
    }

    private func makeActionMenuElements() -> [UIMenuElement] {
        SettingController.SettingContent.ModelController.makeActionMenuElements(
            for: identifier,
            controller: self,
            actionType: .local(
                verify: { [weak self] in await self?.runVerification() },
                evaluate: { [weak self] in EvaluationController.begin(controller: self, model: self?.identifier) },
                openHuggingFace: { [weak self] in self?.openHuggingFace() },
                export: { [weak self] in await self?.exportCurrentModel() },
                delete: { [weak self] in self?.deleteTapped() },
            ),
        )
    }

    @MainActor
    @objc func deleteTapped() {
        presentDeleteConfirmation(
            title: "Delete Model",
            message: "Are you sure you want to delete this model? This action cannot be undone.",
        ) { [weak self] in
            guard let self else { return }
            ModelManager.shared.removeLocalModel(identifier: identifier)
            navigationController?.popViewController(animated: true)
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        let model = ModelManager.shared.localModel(identifier: identifier)

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Metadata"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let idView = ConfigurableInfoView()
        let idInteraction = UIContextMenuInteraction(delegate: SimpleCopyMenuDelegate(
            view: idView,
            title: "Copy",
            actionTitle: "Identifier",
            actionIcon: "person.crop.square.filled.and.at.rectangle",
            copyText: { model?.model_identifier ?? "" },
        ))
        idView.valueLabel.addInteraction(idInteraction)
        idView.configure(icon: .init(systemName: "person.crop.square.filled.and.at.rectangle"))
        idView.configure(title: "Identifier")
        idView.configure(description: "Unique identifier of this model.")
        idView.configure(value: model?.model_identifier ?? "")
        stackView.addArrangedSubviewWithMargin(idView)
        stackView.addArrangedSubview(SeparatorView())

        let sizeView = ConfigurableInfoView()
        let sizeInteraction = UIContextMenuInteraction(delegate: CalibrateSizeMenuDelegate(
            view: sizeView,
            modelId: identifier,
        ))
        sizeView.valueLabel.addInteraction(sizeInteraction)
        sizeView.configure(icon: .init(systemName: "internaldrive"))
        sizeView.configure(title: "Size")
        sizeView.configure(description: "Model size on your local disk.")
        sizeView.configure(value: ByteCountFormatter.string(fromByteCount: Int64(model?.size ?? 0), countStyle: .file))
        stackView.addArrangedSubviewWithMargin(sizeView)
        stackView.addArrangedSubview(SeparatorView())

        let dateView = ConfigurableInfoView()
        let dateInteraction = UIContextMenuInteraction(delegate: SimpleCopyMenuDelegate(
            view: dateView,
            title: "Copy",
            actionTitle: "Download Date",
            actionIcon: "timer",
            copyText: { dateFormatter.string(from: model?.downloaded ?? .distantPast) },
        ))
        dateView.valueLabel.addInteraction(dateInteraction)
        dateView.configure(icon: .init(systemName: "timer"))
        dateView.configure(title: "Download Date")
        dateView.configure(description: "The date when the model was downloaded.")
        dateView.configure(value: dateFormatter.string(from: model?.downloaded ?? .distantPast))
        stackView.addArrangedSubviewWithMargin(dateView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "Metadata of a local model cannot be changed."),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if !ModelCapabilities.localModelEditable.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView()
                    .with(header: "Capabilities"),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            for cap in ModelCapabilities.localModelEditable {
                let view = ConfigurableToggleActionView()
                view.boolValue = model?.capabilities.contains(cap) ?? false
                view.actionBlock = { [weak self] value in
                    guard let self else { return }
                    ModelManager.shared.editLocalModel(identifier: identifier) { model in
                        if value {
                            model.capabilities.insert(cap)
                        } else {
                            model.capabilities.remove(cap)
                        }
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
                    .with(footer: "We cannot determine whether this model includes additional capabilities. However, if supported, features such as visual recognition can be enabled manually here. Please note that if the model does not actually support these capabilities, attempting to enable them may result in errors."),
            ) {
                $0.top /= 2
                $0.bottom = 0
            }
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView()
                    .with(footer: "Local models will use different loaders based on the selected capabilities. For visual models, make sure to enable visual capabilities. Selecting the wrong model capability may result in a crash. If you still cannot load, try switching the model."),
            ) { $0.top /= 2 }

            stackView.addArrangedSubview(SeparatorView())
        }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Parameters"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let contextView = ConfigurableInfoView()
        contextView.configure(icon: .init(systemName: "list.bullet"))
        contextView.configure(title: "Context")
        contextView.configure(description: "The context length for inference refers to the amount of information the model can retain and process at a given time. This context serves as the model’s memory, allowing it to understand and generate responses based on prior input.")
        let contextValue = model?.context.title ?? String(localized: "Not Configured")
        contextView.configure(value: contextValue)
        contextView.setTapBlock { view in
            guard let model else { return }
            let children = ModelContextLength.allCases.map { item in
                UIAction(
                    title: item.title,
                    image: UIImage(systemName: item.icon),
                ) { _ in
                    ModelManager.shared.editLocalModel(identifier: model.id) { $0.context = item }
                    view.configure(value: item.title)
                }
            }
            view.valueLabel.menu = UIMenu(title: String(localized: "Context Length"), children: children)
            view.valueLabel.showsMenuAsPrimaryAction = true
        }
        stackView.addArrangedSubviewWithMargin(contextView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "We cannot determine the context length supported by the model. Please choose the correct configuration here. Configuring a context length smaller than the capacity can save costs. A context that is too long may be truncated during inference."),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())

        let icon = UIImageView().with {
            $0.image = .modelLocal
            $0.tintColor = .label.withAlphaComponent(0.25)
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

    // MARK: - Action Handlers

    @MainActor
    private func runVerification() async {
        guard let model = ModelManager.shared.localModel(identifier: identifier) else { return }
        Indicator.progress(
            title: "Verifying Model",
            controller: self,
        ) { completionHandler in
            let result = await withCheckedContinuation { continuation in
                ModelManager.shared.testLocalModel(model) { result in
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
    private func openHuggingFace() {
        let model = ModelManager.shared.localModel(identifier: identifier)?.model_identifier
        guard let model else {
            assertionFailure()
            return
        }
        guard let url = URL(string: "https://huggingface.co/\(model)") else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func exportCurrentModel() async {
        guard let model = ModelManager.shared.localModel(identifier: identifier) else { return }
        Indicator.progress(
            title: "Exporting Model",
            controller: self,
        ) { updateProgress, completionHandler in
            let progress = Progress(totalUnitCount: 0)
            let progressObserver = progress.observe(\.completedUnitCount, options: [.initial, .new]) { progress, _ in
                let percent = if progress.totalUnitCount > 0 {
                    Int((progress.fractionCompleted * 100).rounded())
                } else {
                    0
                }
                Task { @MainActor in
                    updateProgress("\(percent)%")
                }
            }
            let totalObserver = progress.observe(\.totalUnitCount, options: [.new]) { progress, _ in
                let percent = if progress.totalUnitCount > 0 {
                    Int((progress.fractionCompleted * 100).rounded())
                } else {
                    0
                }
                Task { @MainActor in
                    updateProgress("\(percent)%")
                }
            }
            defer {
                progressObserver.invalidate()
                totalObserver.invalidate()
            }
            let (url, _) = await withCheckedContinuation { continuation in
                ModelManager.shared.pack(model: model, progress: progress) { url, error in
                    continuation.resume(returning: (url, error))
                }
            }
            guard let url else { throw NSError() }
            await completionHandler {
                DisposableExporter(deletableItem: url, title: "Export Model")
                    .run(anchor: self.navigationController?.view ?? self.view)
            }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if !MLX.GPU.isSupported {
            let alert = AlertViewController(
                title: "Unsupported",
                message: "Your device does not support MLX.",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK", attribute: .accent) {
                    context.dispose {
                        self.navigationController?.popViewController()
                    }
                }
            }
            present(alert, animated: true)
        }
    }
}

#if targetEnvironment(macCatalyst)
    extension LocalModelEditorController: UIDocumentPickerDelegate {
        func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt _: [URL]) {
            for cleanableURL in documentPickerExportTempItems {
                try? FileManager.default.removeItem(at: cleanableURL)
            }
            documentPickerExportTempItems.removeAll()
        }
    }
#endif

// MARK: - Menu Delegates

private class SimpleCopyMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var view: ConfigurableInfoView?
    let title: String
    let actionTitle: String
    let actionIcon: String
    let copyText: () -> String

    init(view: ConfigurableInfoView, title: String, actionTitle: String, actionIcon: String, copyText: @escaping () -> String) {
        self.view = view
        self.title = title
        self.actionTitle = actionTitle
        self.actionIcon = actionIcon
        self.copyText = copyText
    }

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(title: title, children: [
                UIAction(
                    title: actionTitle,
                    image: UIImage(systemName: actionIcon),
                ) { [weak self] _ in
                    guard let self, let view else { return }
                    UIPasteboard.general.string = copyText()
                    Indicator.present(title: "Copied", referencingView: view)
                },
            ])
        }
    }
}

private class CalibrateSizeMenuDelegate: NSObject, UIContextMenuInteractionDelegate {
    weak var view: ConfigurableInfoView?
    let modelId: LocalModel.ID

    init(view: ConfigurableInfoView, modelId: LocalModel.ID) {
        self.view = view
        self.modelId = modelId
    }

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            guard let self else { return nil }
            return UIMenu(children: [
                UIAction(
                    title: String(localized: "Calibrate Size"),
                    image: UIImage(systemName: "internaldrive"),
                ) { [weak self] _ in
                    guard let self, let view else { return }
                    let newSize = ModelManager.shared.calibrateLocalModelSize(identifier: modelId)
                    view.configure(value: ByteCountFormatter.string(fromByteCount: Int64(newSize), countStyle: .file))
                },
            ])
        }
    }
}

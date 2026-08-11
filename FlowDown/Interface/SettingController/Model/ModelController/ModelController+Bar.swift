//
//  ModelController+Bar.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import ConfigurableKit
import MLX
import Storage
import UIKit
import UniformTypeIdentifiers

extension SettingController.SettingContent.ModelController {
    private func createCloudModelMenuItems() -> [UIMenuElement] {
        [
            UIAction(
                title: String(localized: "Empty Model"),
                image: .init(systemName: "square.dashed"),
            ) { [weak self] _ in
                guard let self else { return }
                let profile = CloudModel(deviceId: Storage.deviceId)
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                navigationController?.pushViewController(controller, animated: true)
            },
        ]
    }

    private func createLocalModelMenuItems() -> [UIMenuElement] {
        [
            UIAction(
                title: String(localized: "Download @ Hugging Face"),
                image: .init(systemName: "icloud.and.arrow.down"),
            ) { [weak self] _ in
                guard MLX.GPU.isSupported else {
                    let alert = AlertViewController(
                        title: "Unsupported",
                        message: "Your device does not support MLX.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self?.present(alert, animated: true)
                    return
                }
                guard let nav = self?.navigationController else { return }
                nav.pushViewController(HubModelDownloadController(), animated: true)
            },
            UIAction(
                title: String(localized: "Connect @ OLLAMA"),
                image: .init(systemName: "cable.connector.horizontal"),
            ) { [weak self] _ in
                let profile = CloudModel(deviceId: Storage.deviceId)
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                self?.navigationController?.pushViewController(controller, animated: true)
            },
            UIAction(
                title: String(localized: "Connect @ LM Studio"),
                image: .init(systemName: "cable.connector.horizontal"),
            ) { [weak self] _ in
                let profile = CloudModel(deviceId: Storage.deviceId)
                _ = ModelManager.shared.newCloudModel(profile: profile)
                let controller = CloudModelEditorController(identifier: profile.id)
                self?.navigationController?.pushViewController(controller, animated: true)
            },
        ]
    }

    func createAddModelMenuItems() -> [UIMenuElement] {
        [
            UIMenu(
                title: String(localized: "Cloud Model"),
                options: [.displayInline],
                children: createCloudModelMenuItems(),
            ),
            UIMenu(
                title: String(localized: "Local Model"),
                options: [.displayInline],
                children: createLocalModelMenuItems(),
            ),
            UIMenu(
                title: String(localized: "Import Model"),
                options: [.displayInline],
                children: [
                    UIAction(
                        title: String(localized: "Import from File"),
                        image: .init(systemName: "arrow.down.doc"),
                    ) { [weak self] _ in
                        guard let self else { return }
                        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
                            .zip, .propertyList, UTType(filenameExtension: "fdmodel") ?? .data,
                        ], asCopy: true)
                        picker.title = String(localized: "Import Model")
                        picker.delegate = self
                        picker.allowsMultipleSelection = true
                        picker.modalPresentationStyle = .formSheet
                        present(picker, animated: true)
                    },
                ],
            ),
        ]
    }

    func createFilterMenuItems() -> [UIMenuElement] {
        [
            UIAction(
                title: String(localized: "Show Local Models"),
                state: showLocalModels ? .on : .off,
            ) { [weak self] _ in
                self?.showLocalModels.toggle()
            },
            UIAction(
                title: String(localized: "Show Cloud Models"),
                state: showCloudModels ? .on : .off,
            ) { [weak self] _ in
                self?.showCloudModels.toggle()
            },
        ]
    }

    /// Shared menu elements for a specific model row. Extracted so context menus
    /// and any toolbar / accessory menus can reuse the same actions.
    func createModelMenuElements(for itemIdentifier: ModelViewModel) -> [UIMenuElement] {
        switch itemIdentifier.type {
        case .local:
            Self.makeActionMenuElements(
                for: itemIdentifier.identifier,
                controller: self,
                actionType: .local(
                    verify: { [weak self] in
                        guard let self,
                              let model = ModelManager.shared.localModel(identifier: itemIdentifier.identifier)
                        else { return }
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
                    },
                    evaluate: { [weak self] in
                        EvaluationController.begin(controller: self, model: itemIdentifier.identifier)
                    },
                    openHuggingFace: {
                        guard let model = ModelManager.shared.localModel(identifier: itemIdentifier.identifier),
                              let url = URL(string: "https://huggingface.co/\(model.scopeIdentifier)")
                        else { return }
                        UIApplication.shared.open(url)
                    },
                    export: { [weak self] in
                        guard let self,
                              let model = ModelManager.shared.localModel(identifier: itemIdentifier.identifier)
                        else { return }
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
                    },
                    delete: {
                        ModelManager.shared.removeLocalModel(identifier: itemIdentifier.identifier)
                    },
                ),
            )
        case .cloud:
            Self.makeActionMenuElements(
                for: itemIdentifier.identifier,
                controller: self,
                actionType: .cloud(
                    verify: { [weak self] in
                        guard let self,
                              let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier)
                        else { return }
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
                    },
                    evaluate: { [weak self] in
                        EvaluationController.begin(controller: self, model: itemIdentifier.identifier)
                    },
                    export: { [weak self] in
                        self?.exportModel(itemIdentifier)
                    },
                    duplicate: {
                        let newIdentifier = UUID().uuidString
                        ModelManager.shared.editCloudModel(identifier: itemIdentifier.identifier) {
                            $0.update(\.objectId, to: newIdentifier)
                            $0.update(\.model_identifier, to: "")
                            $0.update(\.creation, to: $0.modified)
                        }
                        guard let model = ModelManager.shared.cloudModel(identifier: newIdentifier) else {
                            return
                        }
                        ModelManager.shared.insertCloudModel(model)
                    },
                    delete: {
                        ModelManager.shared.removeCloudModel(identifier: itemIdentifier.identifier)
                    },
                ),
            )
        }
    }

    func createModelMenu(for itemIdentifier: ModelViewModel) -> UIMenu {
        UIMenu(children: createModelMenuElements(for: itemIdentifier))
    }
}

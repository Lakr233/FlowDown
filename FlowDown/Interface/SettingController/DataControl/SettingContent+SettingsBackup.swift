import AlertController
import ConfigurableKit
import UIKit
import UniformTypeIdentifiers

extension SettingController.SettingContent.DataControlController {
    func addSettingsBackupSection() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(
                header: String(localized: "Settings Backup"),
            ),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let importSettings = ConfigurableObject(
            icon: "square.and.arrow.down.on.square",
            title: "Import Settings",
            explain: "Restore a settings backup. The app will exit after import.",
            ephemeralAnnotation: .action { [weak self] controller in
                self?.presentSettingsImportPicker(from: controller)
            },
        ).createView()
        stackView.addArrangedSubviewWithMargin(importSettings)
        stackView.addArrangedSubview(SeparatorView())

        let exportSettings = ConfigurableObject(
            icon: "square.and.arrow.up.on.square",
            title: "Export Settings",
            explain: "Export app preferences and model configurations without conversations.",
            ephemeralAnnotation: .action { controller in
                Indicator.progress(
                    title: "Exporting",
                    controller: controller,
                ) { progressCompletion in
                    let url = try SettingsBackup.export()
                    await progressCompletion {
                        DisposableExporter(deletableItem: url, title: "Export Settings")
                            .run(anchor: controller.view)
                    }
                }
            },
        ).createView()
        stackView.addArrangedSubviewWithMargin(exportSettings)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(
                footer: "Settings backups only include configurable preferences and model selections. Conversations and local model weights remain separate.",
            ),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())
    }

    private func presentSettingsImportPicker(from controller: UIViewController) {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [UTType.json],
            asCopy: true,
        )
        picker.allowsMultipleSelection = false
        picker.delegate = self
        documentPickerImportHandler = { [weak self, weak controller] urls in
            guard let url = urls.first, let controller else {
                self?.documentPickerImportHandler = nil
                return
            }
            self?.documentPickerImportHandler = nil
            self?.performSettingsImport(from: url, controller: controller)
        }
        controller.present(picker, animated: true)
    }

    private func performSettingsImport(from url: URL, controller: UIViewController) {
        Indicator.progress(
            title: "Importing",
            controller: controller,
        ) { progressCompletion in
            let securityScoped = url.startAccessingSecurityScopedResource()
            defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }

            try SettingsBackup.importBackup(from: url)
            await progressCompletion {
                let alert = AlertViewController(
                    title: "Import Complete",
                    message: "FlowDown will close now to apply imported settings.",
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: "OK", attribute: .accent) {
                        context.dispose { terminateApplication() }
                    }
                }
                controller.present(alert, animated: true)
            }
        }
    }
}

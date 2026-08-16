//
//  SettingContent+General.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import AlertController
import Combine
import ConfigurableKit
import Digger
import MarkdownView
import Storage
import UIKit
import UniformTypeIdentifiers

extension SettingController.SettingContent {
    class GeneralController: StackScrollController {
        private var documentPickerImportHandler: (([URL]) -> Void)?
        private var cancellables: Set<AnyCancellable> = []
        private var isProgrammaticallyUpdatingLiveActivityToggle = false

        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "General")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background

            #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
                ConfigurableKit.publisher(forKey: LiveActivitySetting.storageKey, type: Bool.self)
                    .ensureMainThread()
                    .compactMap(\.self)
                    .removeDuplicates()
                    .dropFirst()
                    .sink { [weak self] enabled in
                        guard let self else { return }
                        guard enabled else { return }
                        guard !isProgrammaticallyUpdatingLiveActivityToggle else { return }

                        if StreamAudioEffectSetting.configuredMode() == .off {
                            isProgrammaticallyUpdatingLiveActivityToggle = true
                            LiveActivitySetting.setEnabled(false)
                            isProgrammaticallyUpdatingLiveActivityToggle = false

                            let alert = AlertViewController(
                                title: "Error",
                                message: "Due to system limitations, you must enable audio to use this feature.",
                            ) { context in
                                context.allowSimpleDispose()
                                context.addAction(title: "Dismiss", attribute: .accent) {
                                    context.dispose()
                                }
                            }
                            present(alert, animated: true)
                        }
                    }
                    .store(in: &cancellables)

                ConfigurableKit.publisher(forKey: StreamAudioEffectSetting.storageKey, type: Int.self)
                    .ensureMainThread()
                    .sink { [weak self] rawValue in
                        guard let self else { return }
                        let mode = StreamAudioEffectSetting(rawValue: rawValue ?? StreamAudioEffectSetting.off.rawValue) ?? .off
                        if mode == .off {
                            isProgrammaticallyUpdatingLiveActivityToggle = true
                            LiveActivitySetting.setEnabled(false)
                            isProgrammaticallyUpdatingLiveActivityToggle = false
                        }
                    }
                    .store(in: &cancellables)
            #endif
        }

        let autoCollapse = ConfigurableObject(
            icon: "arrow.down.right.and.arrow.up.left",
            title: "Collapse Reasoning Content",
            explain: "Enable this to automatically collapse reasoning content after the reasoning is completed. This is useful for keeping the chat interface clean and focused on the final response.",
            key: ModelManager.shared.collapseReasoningSectionWhenCompleteKey,
            defaultValue: false,
            annotation: .toggle,
        )
        .createView()

        override func setupContentViews() {
            super.setupContentViews()

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Display",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(BrandingLabel.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(UIUserInterfaceStyle.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(MarkdownTheme.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(CodeBlockCollapseSetting.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "The above setting only adjusts the text size in conversations. To change the font size globally, please go to the system settings, as this app follows the system’s font size preferences.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Chat",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(autoCollapse)
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(StreamAudioEffectSetting.configurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            let importCustomAudioFile = ConfigurableObject(
                icon: "square.and.arrow.down",
                title: "Use Custom Sound Effect",
                explain: "Choose an audio file to use for the custom sound effect.",
                ephemeralAnnotation: .action { [weak self] controller in
                    self?.presentCustomDialTunePicker(from: controller)
                },
            ).createView()
            stackView.addArrangedSubviewWithMargin(importCustomAudioFile)
            stackView.addArrangedSubview(SeparatorView())

            #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
                stackView.addArrangedSubviewWithMargin(LiveActivitySetting.configurableObject.createView())
                stackView.addArrangedSubview(SeparatorView())
            #endif

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "The above setting will take effect at conversation page.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Editor",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(EditorBehavior.useConfirmationOnSendConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(EditorBehavior.pasteAsFileConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(EditorBehavior.compressImageConfigurableObject.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "Regardless of whether image compression is enabled, the EXIF information of the image will be removed. This will delete information such as the shooting date and location.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(
                    header: "Model Selector",
                ),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ChatView.editorModelNameStyle.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(ChatView.editorApplyModelToDefault.createView())
            stackView.addArrangedSubview(SeparatorView())

            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(
                    footer: "If this switch is turned off, the newly selected model in the conversation will not be used for new conversations.",
                ),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
        }

        private func presentCustomDialTunePicker(from controller: UIViewController) {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [UTType.audio],
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
                self?.importCustomDialTune(from: url, controller: controller)
            }
            controller.present(picker, animated: true)
        }

        private func importCustomDialTune(from url: URL, controller: UIViewController) {
            Indicator.progress(
                title: "Updating Custom Sound Effect",
                controller: controller,
            ) { progressCompletion in
                let securityScoped = url.startAccessingSecurityScopedResource()
                defer { if securityScoped { url.stopAccessingSecurityScopedResource() } }

                let data = try Data(contentsOf: url)
                let result = try await AudioTranscoder.transcode(
                    data: data,
                    fileExtension: url.pathExtension.nilIfEmpty,
                    output: .mediumQualityM4A,
                )
                let directory = try SoundEffectPlayer.ensureCustomAudioDirectory()
                let outputURL = directory.appendingPathComponent(SoundEffectPlayer.customAudioFileName)
                try result.data.write(to: outputURL, options: .atomic)

                SoundEffectPlayer.shared.reloadCustomAudio()
                await progressCompletion {
                    Indicator.present(
                        title: "Custom Sound Effect Updated",
                        referencingView: controller.view,
                    )
                }
            }
        }
    }
}

extension SettingController.SettingContent.GeneralController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        documentPickerImportHandler?(urls)
        documentPickerImportHandler = nil
    }

    func documentPickerWasCancelled(_: UIDocumentPickerViewController) {
        documentPickerImportHandler = nil
    }
}

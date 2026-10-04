//
//  EvaluationAssistantController.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import AlertController
import ConfigurableKit
import Storage
import UIKit
import UniformTypeIdentifiers

class EvaluationAssistantController: StackScrollController {
    let identifier: ModelManager.ModelIdentifier
    private var options: EvaluationOptions
    private var manifestCatalog: [EvaluationManifest]

    private var documentPickerImportHandler: (([URL]) -> Void)?

    init(identifier: ModelManager.ModelIdentifier) {
        self.identifier = identifier

        let catalog = EvaluationManifest.all
        manifestCatalog = catalog
        options = EvaluationOptions(modelIdentifier: identifier, manifesets: catalog)

        super.init(nibName: nil, bundle: nil)

        title = String(localized: "Evaluation Assistant")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let moreMenu = UIMenu(children: [
            UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "Import Test Manifest"),
                    image: UIImage(systemName: "square.and.arrow.down"),
                ) { [weak self] _ in
                    guard let self else { return }
                    presentDatasetImportPicker(from: self)
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: String(localized: "Evaluation History"),
                    image: UIImage(systemName: "clock.arrow.circlepath"),
                ) { [weak self] _ in
                    self?.historyTapped()
                },
            ]),
        ])

        let startButton = UIBarButtonItem(
            image: UIImage(systemName: "play.fill"),
            style: .done,
            target: self,
            action: #selector(startTapped),
        )
        startButton.accessibilityLabel = String(localized: "Start")

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: moreMenu,
        )
        moreButton.accessibilityLabel = "More"

        navigationItem.rightBarButtonItems = [startButton, moreButton]
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshEx()
    }

    override func setupContentViews() {
        super.setupContentViews()

        buildModelSection()
        buildRunSettingsSection()
        buildSuitesAndCasesSection()
    }

    @objc private func startTapped() {
        let session = EvaluationSession(options: options)
        do {
            _ = try EvaluationSessionManager.shared.save(session)
            let statusController = EvaluationStatusController(session: session)
            navigationController?.pushViewController(statusController, animated: true)
        } catch {
            let alert = AlertViewController(
                title: "Failed to Start Session",
                message: .init(error.localizedDescription),
            ) { context in
                context.allowSimpleDispose()
            }
            present(alert, animated: true)
        }
    }

    @objc private func historyTapped() {
        let historyController = EvaluationHistoryController()
        navigationController?.pushViewController(historyController)
    }
}

private extension EvaluationAssistantController {
    func attemptsText(_ value: Int) -> String {
        let key: String.LocalizationValue = "\(value) attempts"
        return String(localized: key)
    }

    func refreshUI(delay: TimeInterval = 0) {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(refreshEx),
            object: nil,
        )
        perform(#selector(refreshEx), with: nil, afterDelay: delay)
    }

    @objc func refreshEx() {
        stackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        setupContentViews()
        applySeparatorConstraints()
    }

    func applySeparatorConstraints() {
        stackView
            .subviews
            .compactMap { view -> SeparatorView? in
                if view is SeparatorView {
                    return view as? SeparatorView
                }
                return nil
            }.forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    $0.heightAnchor.constraint(equalToConstant: 1),
                    $0.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                ])
            }
    }

    func buildModelSection() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: String(localized: "Model")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let modelView = ConfigurableInfoView()
        modelView.configure(icon: .init(systemName: "cpu"))
        modelView.configure(title: String(localized: "Evaluation Model"))
        modelView.configure(description: String(localized: "The model used for evaluation."))

        if let localModel = ModelManager.shared.localModel(identifier: identifier) {
            modelView.configure(value: localModel.model_identifier)
        } else if let cloudModel = ModelManager.shared.cloudModel(identifier: identifier) {
            modelView.configure(value: cloudModel.modelFullName)
        } else {
            modelView.configure(value: identifier)
        }

        stackView.addArrangedSubviewWithMargin(modelView)
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: String(localized: "Configuration will be locked after evaluation starts. Make sure the model selection is correct. To adjust temperature and other parameters, set them in the model's Extra Body. Configuration differences directly affect report accuracy.")),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())
    }

    func buildRunSettingsSection() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: String(localized: "Run Settings")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let concurrencyView = ConfigurableInfoView()
        concurrencyView.configure(icon: .init(systemName: "arrow.triangle.2.circlepath"))
        concurrencyView.configure(title: "Concurrency Limit")
        concurrencyView.configure(description: "Sets the maximum number of concurrent network requests. Higher is faster, but too many requests may exhaust resources or trigger API rate limits.")
        do {
            let key: String.LocalizationValue = "\(options.options.maxConcurrentRequests) Requests"
            concurrencyView.configure(value: String(localized: key))
        }
        concurrencyView.use { [weak self, weak concurrencyView] in
            guard let self, let concurrencyView else { return [] }
            let values = [1, 4, 8, 16, 32, 64]
            return values.map { value in
                UIAction(
                    title: {
                        let key: String.LocalizationValue = "\(value) Requests"
                        return String(localized: key)
                    }(),
                    state: self.options.options.maxConcurrentRequests == value ? .on : .off,
                ) { [weak self, weak concurrencyView] _ in
                    guard let self, let concurrencyView else { return }
                    options.options.maxConcurrentRequests = value
                    let key: String.LocalizationValue = "\(value) Requests"
                    concurrencyView.configure(value: String(localized: key))
                }
            }
        }
        stackView.addArrangedSubviewWithMargin(concurrencyView)
        stackView.addArrangedSubview(SeparatorView())

        let shotsView = ConfigurableInfoView()
        shotsView.configure(icon: .init(systemName: "repeat"))
        shotsView.configure(title: String(localized: "Max Attempts"))
        shotsView.configure(description: String(localized: "Maximum executions allowed per test case (including retries). Stop after the first success."))
        shotsView.configure(value: attemptsText(options.options.shots))
        shotsView.use { [weak self, weak shotsView] in
            guard let self, let shotsView else { return [] }
            let values = Array(1 ... 8)
            return values.map { value in
                UIAction(
                    title: self.attemptsText(value),
                    state: self.options.options.shots == value ? .on : .off,
                ) { [weak self, weak shotsView] _ in
                    guard let self, let shotsView else { return }
                    options.options.shots = value
                    shotsView.configure(value: attemptsText(value))
                }
            }
        }
        stackView.addArrangedSubviewWithMargin(shotsView)
        stackView.addArrangedSubview(SeparatorView())
    }

    func buildSuitesAndCasesSection() {
        let enabledManifests = options.manifesets
        guard !enabledManifests.isEmpty else {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView()
                    .with(footer: "No manifest selected."),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            return
        }

        for manifest in enabledManifests {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView()
                    .with(header: String(localized: manifest.title)),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())

            for suite in manifest.suites {
                let suiteView = ConfigurableToggleActionView()
                suiteView.boolValue = !isSuiteExcluded(suite.id)
                suiteView.actionBlock = { [weak self] enabled in
                    guard let self else { return }
                    setSuiteExcluded(suite.id, excluded: !enabled)
                    refreshUI(delay: 2)
                }
                suiteView.configure(icon: .init(systemName: "folder"))
                suiteView.configure(title: String("\(String(localized: suite.title)) \(suite.cases.count)"))
                suiteView.configure(description: suite.description)
                stackView.addArrangedSubviewWithMargin(suiteView)
                stackView.addArrangedSubview(SeparatorView())
            }
        }
    }

    func isSuiteExcluded(_ id: EvaluationManifest.Suite.ID) -> Bool {
        options.excludedSuites.contains(id)
    }

    func setSuiteExcluded(_ id: EvaluationManifest.Suite.ID, excluded: Bool) {
        if excluded {
            if !options.excludedSuites.contains(id) {
                options.excludedSuites.append(id)
            }
        } else {
            options.excludedSuites.removeAll(where: { $0 == id })
        }
    }

    func presentDatasetImportPicker(from controller: UIViewController) {
        // Keep this type strictly conforming to `public.data`.
        let fdemType = UTType(exportedAs: "wiki.qaq.fdem", conformingTo: .data)
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [fdemType],
            asCopy: true,
        )
        picker.allowsMultipleSelection = true
        picker.delegate = self
        documentPickerImportHandler = { [weak self] urls in
            guard let self else {
                self?.documentPickerImportHandler = nil
                return
            }
            documentPickerImportHandler = nil
            performDatasetImport(urls: urls)
        }
        controller.present(picker, animated: true)
    }

    func performDatasetImport(urls: [URL]) {
        guard !urls.isEmpty else { return }

        Indicator.progress(
            title: "Importing Dataset",
            controller: self,
        ) { completionHandler in
            var imported: [EvaluationManifest] = []
            var failure: [Error] = []

            for url in urls {
                do {
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer { if scoped { url.stopAccessingSecurityScopedResource() } }

                    let data = try Data(contentsOf: url)
                    let manifests = try EvaluationAssistantController.decodeImportedManifests(from: data)
                    imported.append(contentsOf: manifests)
                } catch {
                    failure.append(error)
                }
            }

            if imported.isEmpty, let first = failure.first {
                throw first
            }

            await completionHandler {
                if !imported.isEmpty {
                    self.mergeImportedManifests(imported)
                    self.refreshUI()
                }

                if !failure.isEmpty {
                    let alert = AlertViewController(
                        title: "Import Failed",
                        message: "\(imported.count) manifest(s) imported successfully, \(failure.count) failed.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self.present(alert, animated: true)
                } else {
                    Indicator.present(
                        title: "Imported \(imported.count) manifest(s).",
                        preset: .done,
                        referencingView: self.view,
                    )
                }
            }
        }
    }

    func mergeImportedManifests(_ imported: [EvaluationManifest]) {
        for item in imported {
            let titleKey = String(localized: item.title)
            if let existingIndex = manifestCatalog.firstIndex(where: { String(localized: $0.title) == titleKey }) {
                manifestCatalog.remove(at: existingIndex)
                options.manifesets.removeAll(where: { String(localized: $0.title) == titleKey })
            }
            manifestCatalog.append(item)
            options.manifesets.append(item)
        }
    }
}

extension EvaluationAssistantController {
    /// Decodes a manifest file holding either a list of manifests or a single one,
    /// and throws the single-manifest decoding error when neither shape fits.
    nonisolated static func decodeImportedManifests(from data: Data) throws -> [EvaluationManifest] {
        // Prefer JSON.
        let jsonDecoder: JSONDecoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()

        if let list = try? jsonDecoder.decode([EvaluationManifest].self, from: data) {
            return list
        }
        let one = try jsonDecoder.decode(EvaluationManifest.self, from: data)
        return [one]
    }
}

extension EvaluationAssistantController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        documentPickerImportHandler?(urls)
    }
}

import AlertController
import Combine
import FlowDownModelExchange
import SnapKit
import Storage
import UIKit

final class ModelExchangeSelectionController: UIViewController {
    var onCancel: () -> Void = {}
    var onConfirm: ([CloudModel]) -> Void = { _ in }

    private let appName: String
    private let reason: String
    private let capabilities: [ModelExchangeCapability]
    private let multipleSelection: Bool

    private var cancellables: Set<AnyCancellable> = []
    private var lifecycleObservers: [NSObjectProtocol] = []
    private var hasCompleted = false
    private var didShowNoModelsPrompt = false
    private var models: [CloudModel] = []
    private var selectedIds: Set<String> = []

    private let tableView = UITableView(frame: .zero, style: .insetGrouped)

    init(appName: String, reason: String, capabilities: [ModelExchangeCapability], multipleSelection: Bool) {
        self.appName = appName
        self.reason = reason
        self.capabilities = capabilities
        self.multipleSelection = multipleSelection
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Share Models")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        lifecycleObservers.forEach { NotificationCenter.default.removeObserver($0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        setupNavigation()
        setupTableView()
        observeLifecycle()
        bindModels()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.handleEmptyModelsIfNeeded()
        }
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "xmark"),
            style: .plain,
            target: self,
            action: #selector(cancelTapped),
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(confirmTapped),
        )
    }

    private func setupTableView() {
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        tableView.delegate = self
        tableView.dataSource = self
        tableView.allowsMultipleSelection = multipleSelection
        tableView.backgroundColor = .systemGroupedBackground

        tableView.sectionFooterHeight = UITableView.automaticDimension
        tableView.estimatedSectionFooterHeight = 1
        tableView.tableHeaderView = makeTableHeader()
    }

    private func bindModels() {
        ModelManager.shared.cloudModels
            .removeDuplicates()
            .ensureMainThread()
            .sink { [weak self] list in
                guard let self else { return }
                models = list
                tableView.reloadData()
                handleEmptyModelsIfNeeded()
            }
            .store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutTableHeader()
    }

    private func filteredModels() -> [CloudModel] {
        let required = Set(capabilities.compactMap { mapCapability($0) })
        guard !required.isEmpty else {
            return models
        }
        return models.filter { required.isSubset(of: $0.capabilities) }
    }

    private func mapCapability(_ capability: ModelExchangeCapability) -> ModelCapabilities {
        switch capability {
        case .audio: .auditory
        case .visual: .visual
        case .tool: .tool
        case .developerRole: .developerRole
        }
    }

    @objc private func cancelTapped() {
        guard !hasCompleted else { return }
        hasCompleted = true
        dismiss(animated: true) { [onCancel] in
            onCancel()
        }
    }

    @objc private func confirmTapped() {
        let selected = filteredModels().filter { selectedIds.contains($0.id) }
        guard !selected.isEmpty else {
            presentAlert(
                title: "Select a model",
                message: "Pick at least one model to continue.",
            )
            return
        }
        let alert = AlertViewController(
            title: "Confirm Sharing",
            message: "Models may contain credentials or secrets. Share with \(appName)?",
        ) { [weak self] context in
            context.addAction(title: String(localized: "Cancel")) {
                context.dispose {}
            }
            context.addAction(title: String(localized: "Share"), attribute: .accent) { [weak self] in
                context.dispose { [weak self] in
                    guard let self else { return }
                    hasCompleted = true
                    dismiss(animated: true) {
                        self.onConfirm(selected)
                    }
                }
            }
        }
        present(alert, animated: true)
    }

    private func presentAlert(title: String.LocalizationValue, message: String.LocalizationValue) {
        let alert = AlertViewController(
            title: title,
            message: message,
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose {}
            }
        }
        present(alert, animated: true)
    }

    private func handleEmptyModelsIfNeeded() {
        guard !hasCompleted else { return }
        guard !didShowNoModelsPrompt else { return }
        guard view.window != nil else { return }
        guard filteredModels().isEmpty else { return }

        didShowNoModelsPrompt = true
        let alert = AlertViewController(
            title: String(localized: "No Models Available"),
            message: String(localized: "Add models in Settings before sharing."),
        ) { [weak self] context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose { [weak self] in
                    self?.cancelTapped()
                }
            }
        }
        present(alert, animated: true)
    }

    private func makeTableHeader() -> UIView {
        let container = UIView()
        let imageView = UIImageView(image: UIImage(systemName: "square.and.arrow.up.badge.clock"))
        imageView.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 32, weight: .regular)
        imageView.tintColor = .accent
        imageView.contentMode = .scaleAspectFit

        container.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(32)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(32)
            make.bottom.equalToSuperview().inset(32)
        }
        return container
    }

    private func layoutTableHeader() {
        guard let header = tableView.tableHeaderView else { return }
        let targetSize = CGSize(width: tableView.bounds.width, height: UIView.layoutFittingCompressedSize.height)
        let size = header.systemLayoutSizeFitting(
            targetSize,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel,
        )
        if header.frame.size.height != size.height {
            header.frame.size.height = size.height
            tableView.tableHeaderView = header
        }
    }
}

extension ModelExchangeSelectionController {
    static func makePresentedController(
        appName: String,
        reason: String,
        capabilities: [ModelExchangeCapability],
        multipleSelection: Bool,
        onCancel: @escaping () -> Void,
        onConfirm: @escaping ([CloudModel]) -> Void,
        presentingViewController _: UIViewController? = nil,
    ) -> UIViewController {
        let controller = ModelExchangeSelectionController(
            appName: appName,
            reason: reason,
            capabilities: capabilities,
            multipleSelection: multipleSelection,
        )
        controller.onCancel = onCancel
        controller.onConfirm = onConfirm
        controller.preferredContentSize = .init(width: 500, height: 600)

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.view.backgroundColor = .systemGroupedBackground
        navigationController.view.tintColor = .accent
        navigationController.navigationBar.tintColor = .accent
        navigationController.modalTransitionStyle = .coverVertical
        navigationController.modalPresentationStyle = .formSheet
        navigationController.preferredContentSize = controller.preferredContentSize
        navigationController.isModalInPresentation = true

        #if targetEnvironment(macCatalyst)
            return AlertBaseController(
                rootViewController: navigationController,
                preferredWidth: controller.preferredContentSize.width,
                preferredHeight: controller.preferredContentSize.height,
            )
        #else
            return navigationController
        #endif
    }
}

extension ModelExchangeSelectionController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        filteredModels().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let model = filteredModels()[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell") ?? UITableViewCell(
            style: .subtitle,
            reuseIdentifier: "cell",
        )

        var content = cell.defaultContentConfiguration()
        content.text = model.modelDisplayName
        content.secondaryText = model.tags.joined(separator: ", ")
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content

        cell.accessoryType = selectedIds.contains(model.id) ? .checkmark : .none
        cell.selectionStyle = .default
        return cell
    }

    func tableView(_: UITableView, titleForFooterInSection _: Int) -> String? {
        footerText()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        let model = filteredModels()[indexPath.row]
        if !multipleSelection {
            selectedIds = [model.id]
        } else {
            if selectedIds.contains(model.id) {
                selectedIds.remove(model.id)
            } else {
                selectedIds.insert(model.id)
            }
        }
        tableView.reloadData()
    }

    func tableView(_: UITableView, didDeselectRowAt indexPath: IndexPath) {
        guard multipleSelection else { return }
        let model = filteredModels()[indexPath.row]
        selectedIds.remove(model.id)
    }

    private func footerText() -> String {
        let caps = ModelExchangeCapability.summary(from: capabilities)
        return [
            String(localized: "\(appName) is requesting access to your models."),
            String(localized: "Model(s) listed here are capable of: \(caps). Your models are encrypted during this sharing session, and can only be read by \(appName). But be aware that models may contain sensitive information such as credentials or secrets."),
        ]
        .joined(separator: "\n\n")
    }

    private func observeLifecycle() {
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification,
        ]
        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.handleAppInactive()
            }
            lifecycleObservers.append(token)
        }
    }

    private func handleAppInactive() {
        guard !hasCompleted else { return }
        hasCompleted = true
        dismiss(animated: true) { [onCancel] in
            onCancel()
        }
    }
}

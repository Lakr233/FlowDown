// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Layout ported from Irisin's WelcomeRepositoriesController (grey notice over
// an inset grouped list, a footnote under it) and its candidate cell's tinted
// capsule button, through Apelin's WelcomeListPage. The rows are FlowDown's.
//
//  WelcomeModelPage.swift
//  FlowDown
//

import ChatClientKit
import Combine
import SnapKit
import Storage
import UIKit

/// Choose a Model: Apple Intelligence where it runs, a local download where
/// MLX runs, and a cloud service everywhere. Each row opens the same page
/// Settings does, inside the welcome; a row that already has a model shows a
/// checkmark. Next is always available.
final class WelcomeModelPage: WelcomeListPage {
    nonisolated enum Section: Hashable {
        /// No rows: the introduction over the list.
        case notice
        case models
    }

    nonisolated enum Row: Hashable {
        case appleIntelligence
        case localModel
        case cloudModel
    }

    private lazy var dataSource = UITableViewDiffableDataSource<Section, Row>(
        tableView: tableView,
    ) { [unowned self] tableView, indexPath, row in
        let cell = tableView.dequeueReusableCell(withIdentifier: "model", for: indexPath) as! WelcomeModelCell
        configure(cell, for: row)
        return cell
    }

    private var cancellables: Set<AnyCancellable> = []
    /// The blank cloud model this page created, reused while it stays blank
    /// so going back and forth does not leave several empty ones behind.
    private var pendingCloudModelID: CloudModel.ID?

    override init(flow: WelcomeFlow) {
        super.init(flow: flow)
        title = String(localized: "Choose a Model")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(WelcomeModelCell.self, forCellReuseIdentifier: "model")
        tableView.dataSource = dataSource
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 64

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.notice, .models])
        snapshot.appendItems(Self.availableRows, toSection: .models)
        dataSource.apply(snapshot, animatingDifferences: false)

        next { [weak self] in
            self?.flow.showData()
        }

        ModelManager.shared.modelChangedPublisher
            .ensureMainThread()
            .sink { [weak self] _ in self?.reconfigureRows() }
            .store(in: &cancellables)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reconfigureRows()
    }

    // MARK: - Rows

    static var isAppleIntelligenceAvailable: Bool {
        ModelManager.shared.appleIntelligenceEnabled
            && PrivateCloudComputeCenter.shared.isOnDeviceModelAvailable
    }

    static var isLocalModelSupported: Bool {
        ModelManager.shared.gpuSupportProvider()
    }

    private static var availableRows: [Row] {
        var rows: [Row] = []
        if isAppleIntelligenceAvailable { rows.append(.appleIntelligence) }
        if isLocalModelSupported { rows.append(.localModel) }
        rows.append(.cloudModel)
        return rows
    }

    private static var appleIntelligenceIdentifier: ModelManager.ModelIdentifier? {
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            return AppleIntelligenceModel.shared.modelIdentifier
        }
        return nil
    }

    private func isDone(_ row: Row) -> Bool {
        switch row {
        case .appleIntelligence:
            guard let identifier = Self.appleIntelligenceIdentifier else { return false }
            return ModelManager.ModelIdentifier.defaultModelForConversation == identifier
        case .localModel:
            return !ModelManager.shared.localModels.value.isEmpty
        case .cloudModel:
            return ModelManager.shared.cloudModels.value.contains { !$0.model_identifier.isEmpty }
        }
    }

    private func configure(_ cell: WelcomeModelCell, for row: Row) {
        let done = isDone(row)
        switch row {
        case .appleIntelligence:
            cell.configure(
                symbol: "sparkles",
                title: "Apple Intelligence",
                detail: String(localized: "Built into this device. Ready to use."),
                accessory: done ? .selected : .use({ [weak self] in self?.useAppleIntelligence() }),
            )
        case .localModel:
            cell.configure(
                symbol: "cpu.fill",
                title: String(localized: "Download a Local Model"),
                detail: String(localized: "Runs offline on this device. Takes up storage space."),
                accessory: done ? .done : .disclosure,
            )
        case .cloudModel:
            cell.configure(
                symbol: "network",
                title: String(localized: "Connect a Cloud Service"),
                detail: String(localized: "OpenAI-compatible services, Ollama, LM Studio, and more."),
                accessory: done ? .done : .disclosure,
            )
        }
    }

    private func reconfigureRows() {
        guard isViewLoaded else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Actions

    private func useAppleIntelligence() {
        guard let identifier = Self.appleIntelligenceIdentifier else { return }
        ModelManager.ModelIdentifier.defaultModelForConversation = identifier
        reconfigureRows()
    }

    private func downloadLocalModel() {
        push(HubModelDownloadController())
    }

    /// The same as Settings' Add Model, Empty Model: a blank cloud model,
    /// then its editor.
    private func connectCloudService() {
        let identifier: CloudModel.ID
        if let pending = pendingCloudModelID,
           let model = ModelManager.shared.cloudModel(identifier: pending),
           model.model_identifier.isEmpty,
           model.endpoint.isEmpty
        {
            identifier = pending
        } else {
            let profile = CloudModel(deviceId: Storage.deviceId)
            _ = ModelManager.shared.newCloudModel(profile: profile)
            identifier = profile.id
            pendingCloudModelID = identifier
        }
        push(CloudModelEditorController(identifier: identifier))
    }

    /// Settings' own pages, pushed without the onboarding's large titles.
    private func push(_ controller: UIViewController) {
        controller.navigationItem.largeTitleDisplayMode = .never
        navigationController?.pushViewController(
            controller,
            animated: !UIAccessibility.isReduceMotionEnabled,
        )
    }

    // MARK: - Table View

    @objc func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        switch dataSource.itemIdentifier(for: indexPath) {
        case .appleIntelligence:
            useAppleIntelligence()
        case .localModel:
            downloadLocalModel()
        case .cloudModel:
            connectCloudService()
        case nil:
            break
        }
    }

    @objc func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard dataSource.sectionIdentifier(for: section) == .notice else { return nil }
        var configuration = UIListContentConfiguration.groupedHeader()
        configuration.textProperties.font = WelcomeStyle.subtitleFont
        configuration.textProperties.color = WelcomeStyle.detailColor
        configuration.textProperties.transform = .none
        return text(
            configuration,
            String(localized: "You need a model to start chatting. Pick one now, or add one later in Settings."),
        )
    }

    /// The introduction has no rows; its section adds no footer space
    /// between it and the list.
    @objc func tableView(_: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        dataSource.sectionIdentifier(for: section) == .notice
            ? .leastNormalMagnitude
            : UITableView.automaticDimension
    }

    @objc func tableView(_: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard dataSource.sectionIdentifier(for: section) == .models else { return nil }
        var configuration = UIListContentConfiguration.groupedFooter()
        configuration.textProperties.font = WelcomeStyle.detailFont
        configuration.textProperties.color = WelcomeStyle.detailColor
        return text(configuration, String(localized: "You can add more models anytime in Settings."))
    }
}

/// One way to get a model: a 20 pt symbol in a 28 pt box, a title over a
/// one-line explanation, and on the trailing edge either Use, a disclosure
/// indicator or the checkmark of a row that is done.
final class WelcomeModelCell: UITableViewCell {
    enum Accessory {
        /// The tinted capsule button, as Irisin's Add.
        case use(() -> Void)
        /// Use, once chosen: a checkmark read as Selected.
        case selected
        case disclosure
        /// A model of this kind exists.
        case done
    }

    private var onUse: (() -> Void)?
    private lazy var useButton: UIButton = {
        let button = UIButton(configuration: .tinted())
        button.addAction(UIAction { [weak self] _ in self?.onUse?() }, for: .touchUpInside)
        return button
    }()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60).isActive = true
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func configure(symbol: String, title: String, detail: String, accessory: Accessory) {
        var content = UIListContentConfiguration.subtitleCell()
        content.image = UIImage(
            systemName: symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 20, weight: .medium),
        )
        content.imageProperties.tintColor = WelcomeStyle.accent
        content.imageProperties.reservedLayoutSize = CGSize(width: 28, height: 28)
        content.text = title
        content.textProperties.font = .preferredFont(forTextStyle: .body)
        content.textProperties.color = WelcomeStyle.titleColor
        content.secondaryText = detail
        content.secondaryTextProperties.font = WelcomeStyle.detailFont
        content.secondaryTextProperties.color = WelcomeStyle.detailColor
        content.textToSecondaryTextVerticalPadding = 2
        content.directionalLayoutMargins.top = 10
        content.directionalLayoutMargins.bottom = 10
        contentConfiguration = content

        onUse = nil
        accessoryType = .none
        accessoryView = nil
        accessibilityTraits.remove(.selected)
        switch accessory {
        case let .use(action):
            onUse = action
            var configuration = UIButton.Configuration.tinted()
            configuration.buttonSize = .small
            configuration.cornerStyle = .capsule
            configuration.baseForegroundColor = WelcomeStyle.accent
            configuration.baseBackgroundColor = WelcomeStyle.accent
            configuration.title = String(localized: "Use")
            useButton.configuration = configuration
            useButton.accessibilityLabel = String(localized: "Use")
            useButton.isUserInteractionEnabled = true
            useButton.sizeToFit()
            accessoryView = useButton
        case .selected:
            // the same checkmark as a row that is done; the trait reads it
            // as Selected
            accessoryView = Self.checkmark()
            accessibilityTraits.insert(.selected)
        case .disclosure:
            accessoryType = .disclosureIndicator
        case .done:
            accessoryView = Self.checkmark()
            accessibilityTraits.insert(.selected)
        }
    }

    private static func checkmark() -> UIView {
        let check = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        check.tintColor = WelcomeStyle.accent
        check.sizeToFit()
        return check
    }
}

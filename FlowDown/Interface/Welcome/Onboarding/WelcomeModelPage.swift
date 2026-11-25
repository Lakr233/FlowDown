// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Layout ported from Irisin's WelcomeRepositoriesController (grey notice over
// an inset grouped list), through Apelin's WelcomeListPage. The rows are
// FlowDown's.
//
//  WelcomeModelPage.swift
//  FlowDown
//

import ChatClientKit
import Combine
import SnapKit
import Storage
import UIKit

/// Choose a Model: the two Apple Intelligence switches from Settings >
/// Inference where they exist, then a cloud service everywhere and a local
/// download where MLX runs. Those two rows open the same pages Settings does,
/// inside the welcome; a row that already has a model shows a checkmark. Next
/// is always available.
final class WelcomeModelPage: WelcomeListPage {
    nonisolated enum Section: Hashable {
        /// No rows: the introduction over the list.
        case notice
        case appleIntelligence
        case other
    }

    nonisolated enum Row: Hashable {
        case appleIntelligence
        case privateCloudCompute
        case cloudModel
        case localModel
    }

    private lazy var dataSource = UITableViewDiffableDataSource<Section, Row>(
        tableView: tableView,
    ) { [unowned self] tableView, indexPath, row in
        let cell = tableView.dequeueReusableCell(withIdentifier: "model", for: indexPath)
        configure(cell, for: row)
        return cell
    }

    /// The switches in Settings > Inference, on the same stored values.
    private lazy var appleIntelligenceSwitch = makeSwitch { isOn in
        ModelManager.shared.appleIntelligenceEnabled = isOn
    }

    private lazy var privateCloudComputeSwitch = makeSwitch { isOn in
        ModelManager.shared.privateCloudComputeEnabled = isOn
    }

    private var cancellables: Set<AnyCancellable> = []

    override init(flow: WelcomeFlow) {
        super.init(flow: flow)
        title = String(localized: "Choose a Model")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "model")
        tableView.dataSource = dataSource

        var snapshot = NSDiffableDataSourceSnapshot<Section, Row>()
        snapshot.appendSections([.notice])
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            snapshot.appendSections([.appleIntelligence])
            snapshot.appendItems([.appleIntelligence, .privateCloudCompute], toSection: .appleIntelligence)
        }
        snapshot.appendSections([.other])
        snapshot.appendItems([.cloudModel, .localModel], toSection: .other)
        dataSource.apply(snapshot, animatingDifferences: false)

        next { [weak self] in
            self?.flow.showSync()
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Back from the cloud model editor: a model left blank goes away.
        // Not before the page is back, so a swipe back the user cancels
        // keeps the editor's model.
        WelcomeExperience.discardBlankPendingCloudModel()
    }

    // MARK: - Rows

    /// Why the on-device model can't run, as Settings says it, or nil.
    private static var appleIntelligenceReason: String? {
        guard #available(iOS 26.0, macCatalyst 26.0, *),
              !PrivateCloudComputeCenter.shared.isOnDeviceModelAvailable
        else { return nil }
        return AppleIntelligenceModel.shared.availabilityDescription.map { String(localized: $0) }
    }

    private func configure(_ cell: UITableViewCell, for row: Row) {
        var content = cell.defaultContentConfiguration()
        content.textProperties.color = WelcomeStyle.titleColor
        cell.tintColor = WelcomeStyle.accent
        cell.selectionStyle = .default
        cell.accessoryView = nil
        cell.accessoryType = .none
        switch row {
        case .appleIntelligence:
            content.text = AppleIntelligenceModelNames.local
            update(
                appleIntelligenceSwitch,
                isOn: ModelManager.shared.appleIntelligenceEnabled,
                isAvailable: PrivateCloudComputeCenter.shared.isOnDeviceModelAvailable,
            )
            cell.accessoryView = appleIntelligenceSwitch
            cell.selectionStyle = .none
        case .privateCloudCompute:
            content.text = AppleIntelligenceModelNames.privateCloudCompute
            update(
                privateCloudComputeSwitch,
                isOn: ModelManager.shared.privateCloudComputeEnabled,
                isAvailable: PrivateCloudComputeCenter.shared.isAvailable,
            )
            cell.accessoryView = privateCloudComputeSwitch
            cell.selectionStyle = .none
        case .cloudModel:
            content.text = String(localized: "Connect a Cloud Service")
            let isDone = ModelManager.shared.cloudModels.value.contains { !$0.model_identifier.isEmpty }
            cell.accessoryType = isDone ? .checkmark : .disclosureIndicator
        case .localModel:
            content.text = String(localized: "Download a Local Model")
            let isDone = !ModelManager.shared.localModels.value.isEmpty
            cell.accessoryType = isDone ? .checkmark : .disclosureIndicator
        }
        cell.contentConfiguration = content
    }

    private func makeSwitch(_ onChange: @escaping (Bool) -> Void) -> UISwitch {
        let view = UISwitch()
        view.onTintColor = WelcomeStyle.accent
        view.addAction(UIAction { [weak view] _ in
            guard let view else { return }
            onChange(view.isOn)
            ModelManager.shared.checkDefaultModels()
        }, for: .valueChanged)
        return view
    }

    /// A model that can't run here shows its switch off and greyed out, as
    /// Settings does without the entitlement. The stored value is kept.
    private func update(_ view: UISwitch, isOn: Bool, isAvailable: Bool) {
        view.isEnabled = isAvailable
        view.setOn(isAvailable && isOn, animated: false)
    }

    private func reconfigureRows() {
        guard isViewLoaded else { return }
        var snapshot = dataSource.snapshot()
        snapshot.reconfigureItems(snapshot.itemIdentifiers)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Actions

    private func downloadLocalModel() {
        push(HubModelDownloadController())
    }

    /// The same as Settings' Add Model, Empty Model: a blank cloud model,
    /// then its editor. The welcome remembers the model, and removes it if it
    /// is still blank when this page shows again or the welcome ends.
    private func connectCloudService() {
        WelcomeExperience.discardBlankPendingCloudModel()
        let profile = CloudModel(deviceId: Storage.deviceId)
        let model = ModelManager.shared.newCloudModel(profile: profile)
        WelcomeExperience.setPendingCloudModel(model.id)
        push(CloudModelEditorController(identifier: model.id))
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
        case .localModel:
            downloadLocalModel()
        case .cloudModel:
            connectCloudService()
        case .appleIntelligence, .privateCloudCompute, nil:
            break
        }
    }

    @objc func tableView(_: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        switch dataSource.sectionIdentifier(for: section) {
        case .notice:
            var configuration = UIListContentConfiguration.groupedHeader()
            configuration.textProperties.font = WelcomeStyle.subtitleFont
            configuration.textProperties.color = WelcomeStyle.detailColor
            configuration.textProperties.transform = .none
            return text(
                configuration,
                String(localized: "Pick a model to start chatting, or add one later in Settings."),
            )
        case .appleIntelligence:
            return text(.groupedHeader(), String(localized: "Apple Intelligence"))
        case .other:
            return text(.groupedHeader(), String(localized: "Other Models"))
        case nil:
            return nil
        }
    }

    /// The introduction has no rows; its section adds no footer space
    /// between it and the list.
    @objc func tableView(_: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        dataSource.sectionIdentifier(for: section) == .notice
            ? .leastNormalMagnitude
            : UITableView.automaticDimension
    }

    /// One reason, in Settings' words: the on-device model's, or Private
    /// Cloud Compute's where only that one can't run.
    static func footerReason(local: String?, privateCloudCompute: String?) -> String? {
        [local, privateCloudCompute].compactMap(\.self).first { !$0.isEmpty }
    }

    /// Only a model that can't run here has a footer: why.
    @objc func tableView(_: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard dataSource.sectionIdentifier(for: section) == .appleIntelligence,
              let reason = Self.footerReason(
                  local: Self.appleIntelligenceReason,
                  privateCloudCompute: PrivateCloudComputeCenter.shared.unavailableText,
              )
        else { return nil }
        var configuration = UIListContentConfiguration.groupedFooter()
        configuration.textProperties.font = WelcomeStyle.detailFont
        configuration.textProperties.color = WelcomeStyle.detailColor
        return text(configuration, reason)
    }
}

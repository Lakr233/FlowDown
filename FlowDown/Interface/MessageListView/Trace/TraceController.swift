//
//  TraceController.swift
//  FlowDown
//

import Storage
import UIKit

/// The trace behind a summary, in a sheet; the conversation shows one
/// summary. Each step in order — a thought, a call — is a row, its kind
/// over a line of its detail (`TraceStep`), and a row with more opens that
/// step whole (`TraceStepController`). It follows the run: steps are added
/// and rows reconfigured in place, so the reader's scroll and open page
/// stay, and the open page shows its step as it grows.
final class TraceController: UITableViewController {
    let summaryID: String
    /// A call's arguments as JSON, looked up when its row is made.
    private let arguments: (Message.ID) -> String?
    private var summary: MessageListView.ActivitySummary
    /// Each row as last shown, with the step it was made from: a step that
    /// did not change is not read again, so a call's arguments are decoded
    /// once, not on every update of the run.
    private var shown: [String: (step: MessageListView.ActivitySummary.Step, row: TraceStep)] = [:]
    private static let cellIdentifier = "Step"

    private lazy var dataSource = UITableViewDiffableDataSource<Int, String>(
        tableView: tableView,
    ) { [weak self] table, indexPath, id in
        let cell = table.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        guard let row = self?.shown[id]?.row else { return cell }
        var content = UIListContentConfiguration.subtitleCell()
        content.text = row.title
        content.textProperties.numberOfLines = 1
        content.secondaryText = row.subtitle.isEmpty ? nil : row.subtitle
        content.secondaryTextProperties.numberOfLines = 1
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        cell.accessoryType = row.hasDetail ? .disclosureIndicator : .none
        cell.selectionStyle = row.hasDetail ? .default : .none
        return cell
    }

    init(summary: MessageListView.ActivitySummary, arguments: @escaping (Message.ID) -> String?) {
        self.summary = summary
        summaryID = summary.id
        self.arguments = arguments
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(summary:arguments:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Trace")
        navigationItem.backButtonDisplayMode = .minimal
        // The app clears every table's background; a grouped list sits on its own.
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
        show(summary)
    }

    func show(_ summary: MessageListView.ActivitySummary) {
        self.summary = summary
        guard isViewLoaded else { return }
        var shown: [String: (step: MessageListView.ActivitySummary.Step, row: TraceStep)] = [:]
        var changed: [String] = []
        var ids: [String] = []
        for step in summary.steps where shown[step.id] == nil {
            let row: TraceStep
            if let known = self.shown[step.id], known.step == step {
                row = known.row
            } else {
                row = TraceStep(step, arguments: arguments(for: step))
                if self.shown[step.id] != nil {
                    changed.append(step.id)
                }
            }
            shown[step.id] = (step, row)
            ids.append(step.id)
        }
        self.shown = shown
        var snapshot = NSDiffableDataSourceSnapshot<Int, String>()
        snapshot.appendSections([0])
        snapshot.appendItems(ids)
        snapshot.reconfigureItems(changed)
        dataSource.apply(snapshot, animatingDifferences: view.window != nil)
        for case let page as TraceStepController in navigationController?.viewControllers ?? [] {
            if let row = shown[page.stepID]?.row {
                page.show(row.body)
            }
        }
    }

    private func arguments(for step: MessageListView.ActivitySummary.Step) -> String? {
        guard case let .tool(messageID, _) = step else { return nil }
        return arguments(messageID)
    }

    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        dataSource.itemIdentifier(for: indexPath).flatMap { shown[$0]?.row.hasDetail } == true
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let id = dataSource.itemIdentifier(for: indexPath),
              let row = shown[id]?.row, row.hasDetail
        else { return }
        let page = TraceStepController(stepID: id, body: row.body, title: row.title)
        navigationController?.pushViewController(page, animated: true)
    }
}

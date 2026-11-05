//
//  TraceSearchController.swift
//  FlowDown
//

import Storage
import UIKit

/// What a web search's page shows.
struct TraceSearch: Hashable {
    let queries: [String]
    /// How the search went, on one line.
    let status: String
    let sources: [Message.WebSearchStatus.SearchResult]
}

/// One web search of the trace, opened from its row: what it looked for and
/// how that went, then every source it found. Tapping a source opens it, and
/// its context menu shares it or opens it in the default browser.
final class TraceSearchController: UITableViewController {
    let stepID: String
    private var search: TraceSearch
    private static let cellIdentifier = "Row"
    private static let queriesSection = 0
    private static let sourcesSection = 1

    init(stepID: String, search: TraceSearch, title: String) {
        self.stepID = stepID
        self.search = search
        super.init(style: .insetGrouped)
        self.title = title
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(stepID:search:title:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        // The app clears every table's background; a grouped list sits on its own.
        tableView.backgroundColor = .systemGroupedBackground
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Self.cellIdentifier)
    }

    /// A search that did not change keeps the reader's scroll and highlight.
    func show(_ search: TraceSearch) {
        guard search != self.search else { return }
        self.search = search
        guard isViewLoaded else { return }
        tableView.reloadData()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        2
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == Self.queriesSection ? search.queries.count : search.sources.count
    }

    override func tableView(_: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == Self.sourcesSection && !search.sources.isEmpty ? String(localized: "Web Search Results") : nil
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        section == Self.queriesSection ? search.status : nil
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: Self.cellIdentifier, for: indexPath)
        var content = UIListContentConfiguration.subtitleCell()
        if let source = source(at: indexPath) {
            content.text = source.title.isEmpty ? source.url.absoluteString : source.title
            content.textProperties.numberOfLines = 2
            content.textProperties.color = .accent
            content.secondaryText = source.url.host ?? source.url.absoluteString
            content.secondaryTextProperties.numberOfLines = 1
            content.secondaryTextProperties.color = .secondaryLabel
            cell.selectionStyle = .default
            cell.accessibilityTraits = .link
        } else {
            content.text = search.queries[indexPath.row]
            cell.selectionStyle = .none
            cell.accessibilityTraits = .staticText
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        source(at: indexPath) != nil
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let source = source(at: indexPath) else { return }
        Indicator.present(source.url, referencedView: tableView)
    }

    override func tableView(
        _ tableView: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let source = source(at: indexPath) else { return nil }
        return UIContextMenuConfiguration(actionProvider: { [weak self, weak tableView] _ in
            UIMenu(title: source.url.host ?? "", children: [
                UIAction(title: String(localized: "View"), image: UIImage(systemName: "eye")) { _ in
                    Indicator.present(source.url, referencedView: tableView)
                },
                UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    guard let anchor = tableView?.cellForRow(at: indexPath) ?? self?.view else { return }
                    DisposableExporter(data: Data(source.url.absoluteString.utf8), pathExtension: "txt")
                        .run(anchor: anchor, mode: .text)
                },
                UIAction(title: String(localized: "Open in Default Browser"), image: UIImage(systemName: "safari")) { _ in
                    UIApplication.shared.open(source.url)
                },
            ])
        })
    }

    private func source(at indexPath: IndexPath) -> Message.WebSearchStatus.SearchResult? {
        guard indexPath.section == Self.sourcesSection, search.sources.indices.contains(indexPath.row) else { return nil }
        return search.sources[indexPath.row]
    }
}

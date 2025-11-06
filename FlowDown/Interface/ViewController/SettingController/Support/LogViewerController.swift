//
//  LogViewerController.swift
//  FlowDown
//

import Storage
import UIKit

final class LogViewerController: UIViewController, UITableViewDataSource, UITableViewDelegate, UISearchResultsUpdating {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)

    private var allLines: [LogLine] = []
    private var filteredLines: [LogLine] = []

    private var selectedLevels: Set<LogLevel> = [.debug, .info, .error]
    private var selectedCategories: Set<String> = []
    private var allCategories: Set<String> = []

    private var isSearching: Bool {
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return searchController.isActive && !text.isEmpty
    }

    private var displayLines: [LogLine] {
        isSearching ? filteredLines : allLines
    }

    struct LogLine {
        let timestamp: String
        let level: LogLevel
        let category: String
        let message: String
        let fullText: String

        init?(from line: String) {
            guard !line.isEmpty else { return nil }

            // Try to parse format: "2025-10-30T12:34:56.789Z [DEBUG] [Category] message"
            let components = line.components(separatedBy: " ")

            // Check if it's a properly formatted log line
            if components.count >= 4,
               components[0].contains("T"), // Timestamp contains 'T'
               components[1].hasPrefix("["), components[1].hasSuffix("]"), // Level in brackets
               components[2].hasPrefix("["), components[2].hasSuffix("]")
            { // Category in brackets
                timestamp = components[0]

                // Extract level
                let levelStr = components[1].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                if let parsedLevel = LogLevel(rawValue: levelStr) {
                    level = parsedLevel
                } else {
                    level = .info // Default to info if level is unknown
                }

                // Extract category
                category = components[2].trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

                // Rest is message
                message = components.dropFirst(3).joined(separator: " ")
                fullText = line
            } else {
                // Fallback: treat as unformatted log line
                timestamp = ""
                level = .info
                category = "System"
                message = line
                fullText = line
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = String(localized: "Logs")
        view.backgroundColor = .systemBackground

        setupSearchController()
        setupMenuButton()
        setupTableView()
        reload()
    }

    private func setupSearchController() {
        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search logs...")
        searchController.searchBar.autocapitalizationType = .none
        searchController.searchBar.autocorrectionType = .no
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true
    }

    private func setupMenuButton() {
        // Use a custom button to avoid autolayout constraint warnings
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "ellipsis.circle"), for: .normal)
        button.showsMenuAsPrimaryAction = true
        button.menu = createMenu()

        // Set explicit size to avoid constraint conflicts
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)

        let menuButton = UIBarButtonItem(customView: button)
        navigationItem.rightBarButtonItem = menuButton
    }

    private func createMenu() -> UIMenu {
        // Level filter submenu
        let levelActions = [LogLevel.debug, .info, .error].map { level in
            UIAction(
                title: level.rawValue,
                image: selectedLevels.contains(level) ? UIImage(systemName: "checkmark") : nil,
                handler: { [weak self] _ in
                    self?.toggleLevel(level)
                }
            )
        }
        let levelMenu = UIMenu(
            title: String(localized: "Filter by Level"),
            image: UIImage(systemName: "slider.horizontal.3"),
            children: levelActions
        )

        // Category filter submenu
        var categoryActions: [UIAction] = []
        if !allCategories.isEmpty {
            categoryActions.append(UIAction(
                title: String(localized: "All Categories"),
                image: selectedCategories.isEmpty ? UIImage(systemName: "checkmark") : nil,
                handler: { [weak self] _ in
                    self?.selectedCategories.removeAll()
                    self?.applyFilters()
                    self?.updateMenu()
                }
            ))
            categoryActions.append(contentsOf: allCategories.sorted().map { category in
                UIAction(
                    title: category,
                    image: selectedCategories.contains(category) ? UIImage(systemName: "checkmark") : nil,
                    handler: { [weak self] _ in
                        self?.toggleCategory(category)
                    }
                )
            })
        }
        let categoryMenu = UIMenu(
            title: String(localized: "Filter by Category"),
            image: UIImage(systemName: "tag"),
            children: categoryActions.isEmpty ? [UIAction(title: String(localized: "No categories"), handler: { _ in })] : categoryActions
        )

        // Actions
        let refreshAction = UIAction(
            title: String(localized: "Refresh"),
            image: UIImage(systemName: "arrow.clockwise"),
            handler: { [weak self] _ in
                self?.reload()
            }
        )

        let shareAction = UIAction(
            title: String(localized: "Share"),
            image: UIImage(systemName: "square.and.arrow.up"),
            handler: { [weak self] _ in
                self?.shareLog()
            }
        )

        let clearAction = UIAction(
            title: String(localized: "Clear"),
            image: UIImage(systemName: "trash"),
            attributes: .destructive,
            handler: { [weak self] _ in
                self?.clearLog()
            }
        )

        return UIMenu(children: [
            levelMenu,
            categoryMenu,
            UIMenu(options: .displayInline, children: [refreshAction]),
            UIMenu(options: .displayInline, children: [shareAction, clearAction]),
        ])
    }

    private func setupTableView() {
        tableView.dataSource = self
        tableView.delegate = self
        tableView.estimatedRowHeight = 60
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .singleLine
        tableView.backgroundColor = .systemBackground
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func toggleLevel(_ level: LogLevel) {
        if selectedLevels.contains(level) {
            selectedLevels.remove(level)
        } else {
            selectedLevels.insert(level)
        }
        applyFilters()
        updateMenu()
    }

    private func toggleCategory(_ category: String) {
        if selectedCategories.contains(category) {
            selectedCategories.remove(category)
        } else {
            selectedCategories.insert(category)
        }
        applyFilters()
        updateMenu()
    }

    private func updateMenu() {
        // Update menu for custom button view
        if let customView = navigationItem.rightBarButtonItem?.customView as? UIButton {
            customView.menu = createMenu()
        } else {
            navigationItem.rightBarButtonItem?.menu = createMenu()
        }
    }

    private func applyFilters() {
        allLines = parseLogLines()
        tableView.reloadData()
        scrollToBottom()
    }

    private func parseLogLines() -> [LogLine] {
        let text = LogStore.shared.readTail()
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)

        var parsedLines: [LogLine] = []
        var categories = Set<String>()

        for line in lines {
            guard let logLine = LogLine(from: line) else {
                // Log parsing failure for debugging
                print("[LogViewer] Failed to parse line: \(line.prefix(100))")
                continue
            }
            categories.insert(logLine.category)

            // Apply level filter
            guard selectedLevels.contains(logLine.level) else { continue }

            // Apply category filter
            if !selectedCategories.isEmpty, !selectedCategories.contains(logLine.category) {
                continue
            }

            parsedLines.append(logLine)
        }

        allCategories = categories
        print("[LogViewer] Parsed \(parsedLines.count) lines from \(lines.count) total lines")
        return parsedLines
    }

    @objc private func reload() {
        applyFilters()
        updateMenu()
    }

    @objc private func shareLog() {
        let text = LogStore.shared.readTail(maxBytes: 512 * 1024)
        DisposableExporter(data: Data(text.utf8), pathExtension: "txt").run(anchor: view, mode: .text)
    }

    @objc private func clearLog() {
        LogStore.shared.clear()
        reload()
    }

    private func scrollToBottom() {
        guard !displayLines.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let indexPath = IndexPath(row: displayLines.count - 1, section: 0)
            tableView.scrollToRow(at: indexPath, at: .bottom, animated: false)
        }
    }

    // MARK: - UISearchResultsUpdating

    func updateSearchResults(for searchController: UISearchController) {
        guard let searchText = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              !searchText.isEmpty
        else {
            filteredLines = []
            tableView.reloadData()
            return
        }

        let lowercasedSearch = searchText.lowercased()
        filteredLines = allLines.filter { line in
            line.fullText.lowercased().contains(lowercasedSearch)
        }
        tableView.reloadData()
    }

    // MARK: - UITableViewDataSource & Delegate

    func numberOfSections(in _: UITableView) -> Int { 1 }

    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        displayLines.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let id = "LogCell"
        let cell = tableView.dequeueReusableCell(withIdentifier: id) ?? UITableViewCell(style: .subtitle, reuseIdentifier: id)

        let logLine = displayLines[indexPath.row]

        // Configure main text
        cell.textLabel?.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.text = logLine.message

        // Configure detail text (timestamp + category)
        cell.detailTextLabel?.font = .monospacedSystemFont(ofSize: 9, weight: .regular)
        cell.detailTextLabel?.numberOfLines = 1
        if logLine.timestamp.isEmpty {
            cell.detailTextLabel?.text = logLine.category
        } else {
            cell.detailTextLabel?.text = "\(logLine.timestamp) • \(logLine.category)"
        }

        // Color coding by level
        switch logLine.level {
        case .debug:
            cell.textLabel?.textColor = .systemGray
            cell.detailTextLabel?.textColor = .systemGray2
            cell.backgroundColor = .systemBackground
        case .info:
            cell.textLabel?.textColor = .label
            cell.detailTextLabel?.textColor = .secondaryLabel
            cell.backgroundColor = .systemBackground
        case .error:
            cell.textLabel?.textColor = .systemRed
            cell.detailTextLabel?.textColor = .systemRed.withAlphaComponent(0.7)
            cell.backgroundColor = .systemRed.withAlphaComponent(0.05)
        }

        cell.selectionStyle = .none
        return cell
    }

    func tableView(_: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point _: CGPoint) -> UIContextMenuConfiguration? {
        let logLine = displayLines[indexPath.row]

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyAction = UIAction(
                title: String(localized: "Copy"),
                image: UIImage(systemName: "doc.on.doc")
            ) { _ in
                UIPasteboard.general.string = logLine.fullText
            }

            let copyMessageAction = UIAction(
                title: String(localized: "Copy Message"),
                image: UIImage(systemName: "text.quote")
            ) { _ in
                UIPasteboard.general.string = logLine.message
            }

            return UIMenu(children: [copyAction, copyMessageAction])
        }
    }
}

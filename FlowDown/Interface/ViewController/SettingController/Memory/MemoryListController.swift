//
//  MemoryListController.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import AlertController
import SnapKit
import Storage
import UIKit

class MemoryListController: UIViewController {
    private let tableView = UITableView(frame: .zero, style: .plain)
    private let searchController = UISearchController(searchResultsController: nil)
    private var memories: [Memory] = []
    private var filteredMemories: [Memory] = []
    private static let newMemoryPlaceholder = String(localized: "Memory")

    private var isSearching: Bool {
        let text = searchController.searchBar.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return searchController.isActive && !text.isEmpty
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        loadMemories()
    }

    private func setupUI() {
        view.backgroundColor = .background

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = String(localized: "Search memories...")
        searchController.searchBar.searchBarStyle = .minimal
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false
        navigationItem.preferredSearchBarPlacement = .stacked
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            systemItem: .add,
            target: self,
            action: #selector(addMemoryTapped)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "memory-list.add-memory"

        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .init(top: 0, left: 20, bottom: 0, right: 20)
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 120
        tableView.keyboardDismissMode = .interactive
        tableView.register(MemoryCell.self, forCellReuseIdentifier: MemoryCell.identifier)

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    private func loadMemories() {
        Task {
            do {
                let loadedMemories = try await MemoryStore.shared.getAllMemoriesAsync()
                await MainActor.run {
                    self.memories = loadedMemories
                    self.filteredMemories = loadedMemories
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    Logger.database.errorFile("MemoryListController load memories error: \(error)")
                    self.memories = []
                    self.filteredMemories = []
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func searchMemories(query: String) {
        Task {
            do {
                let searchResults = try await MemoryStore.shared.searchMemories(query: query, limit: 50)
                await MainActor.run {
                    self.filteredMemories = searchResults
                    self.tableView.reloadData()
                }
            } catch {
                await MainActor.run {
                    Logger.database.errorFile("MemoryListController search memories error: \(error)")
                    self.filteredMemories = []
                    self.tableView.reloadData()
                }
            }
        }
    }

    private func currentMemories() -> [Memory] {
        isSearching ? filteredMemories : memories
    }

    @objc
    private func addMemoryTapped() {
        Task { [weak self] in
            guard let self else { return }
            do {
                let newMemory = try await MemoryStore.shared.storeMemoryAsync(content: Self.newMemoryPlaceholder)
                let refreshed = try await MemoryStore.shared.getAllMemoriesAsync()
                await MainActor.run {
                    guard let self else { return }
                    self.updateDataSource(with: refreshed)
                    self.presentEditor(for: newMemory, isNew: true)
                }
            } catch {
                await MainActor.run {
                    guard let self else { return }
                    let errorAlert = AlertViewController(
                        title: "Error",
                        message: "Failed to create memory: \(error.localizedDescription)"
                    ) { context in
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self.present(errorAlert, animated: true)
                }
            }
        }
    }

    private func deleteMemory(at indexPath: IndexPath) {
        let memory = currentMemories()[indexPath.row]

        Task {
            do {
                try await MemoryStore.shared.deleteMemoryAsync(id: memory.id)
                await MainActor.run {
                    if self.isSearching {
                        self.filteredMemories.remove(at: indexPath.row)
                        if let originalIndex = self.memories.firstIndex(where: { $0.id == memory.id }) {
                            self.memories.remove(at: originalIndex)
                        }
                    } else {
                        self.memories.remove(at: indexPath.row)
                    }
                    self.tableView.deleteRows(at: [indexPath], with: .fade)
                }
            } catch {
                await MainActor.run {
                    let errorAlert = AlertViewController(
                        title: "Error",
                        message: "Failed to delete memory: \(error.localizedDescription)"
                    ) { context in
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self.present(errorAlert, animated: true)
                }
            }
        }
    }
}

// MARK: - UITableViewDataSource

extension MemoryListController: UITableViewDataSource {
    func tableView(_: UITableView, numberOfRowsInSection _: Int) -> Int {
        currentMemories().count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: MemoryCell.identifier, for: indexPath) as! MemoryCell
        let memory = currentMemories()[indexPath.row]
        cell.configure(with: memory)
        return cell
    }
}

// MARK: - UITableViewDelegate

extension MemoryListController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let memory = currentMemories()[indexPath.row]
        presentEditor(for: memory)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let memory = currentMemories()[indexPath.row]

        let delete = UIContextualAction(style: .destructive, title: "Delete") { [weak self] _, _, completion in
            self?.deleteMemory(at: indexPath)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")

        let edit = UIContextualAction(style: .normal, title: "Edit") { [weak self] _, _, completion in
            self?.presentEditor(for: memory)
            completion(true)
        }
        edit.backgroundColor = .systemBlue
        edit.image = UIImage(systemName: "square.and.pencil")

        let configuration = UISwipeActionsConfiguration(actions: [delete, edit])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        let memory = currentMemories()[indexPath.row]
        return UIContextMenuConfiguration(
            identifier: memory.id as NSString,
            previewProvider: { nil }
        ) { [weak self] _ in
            guard let self else { return nil }
            let editAction = UIAction(title: String(localized: "Edit"), image: UIImage(systemName: "square.and.pencil")) { _ in
                self.presentEditor(for: memory)
            }

            let copyAction = UIAction(title: String(localized: "Copy"), image: UIImage(systemName: "doc.on.doc")) { _ in
                UIPasteboard.general.string = memory.content
            }

            let shareAction = UIAction(title: String(localized: "Share"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                guard let self else { return }
                DisposableExporter(data: Data(memory.content.utf8), pathExtension: "txt").run(anchor: view, mode: .text)
            }

            let deleteAction = UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                guard let self else { return }
                if let currentIndexPath = self.indexPath(for: memory) {
                    deleteMemory(at: currentIndexPath)
                }
            }

            return UIMenu(children: [editAction, copyAction, shareAction, deleteAction])
        }
    }

    func tableView(
        _: UITableView,
        willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
        animator: UIContextMenuInteractionCommitAnimating
    ) {
        guard let identifier = configuration.identifier as? NSString else { return }
        let memoryId = identifier as String
        animator.addCompletion { [weak self] in
            guard let self else { return }
            if let memory = memories.first(where: { $0.id == memoryId }) {
                presentEditor(for: memory)
            }
        }
    }
}

// MARK: - UISearchResultsUpdating

extension MemoryListController: UISearchResultsUpdating {
    func updateSearchResults(for _: UISearchController) {
        if isSearching {
            searchMemories(query: searchController.searchBar.text ?? "")
        } else {
            filteredMemories = memories
            tableView.reloadData()
        }
    }
}

// MARK: - MemoryCell

class MemoryCell: UITableViewCell {
    static let identifier = "MemoryCell"

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private let stackView = UIStackView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        backgroundColor = .clear
        selectionStyle = .default

        stackView.axis = .vertical
        stackView.spacing = 6
        stackView.alignment = .leading

        titleLabel.font = .preferredFont(forTextStyle: .body)
        titleLabel.textColor = .label
        titleLabel.numberOfLines = 0

        detailLabel.font = .preferredFont(forTextStyle: .footnote)
        detailLabel.textColor = .secondaryLabel
        detailLabel.numberOfLines = 0

        stackView.addArrangedSubview(titleLabel)
        stackView.addArrangedSubview(detailLabel)

        contentView.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: 12, left: 16, bottom: 12, right: 16))
        }

        let selectionBackground = UIView()
        selectionBackground.backgroundColor = UIColor.secondarySystemGroupedBackground
        selectedBackgroundView = selectionBackground
    }

    func configure(with memory: Memory) {
        titleLabel.text = memory.content

        var detailComponents: [String] = [Self.dateFormatter.string(from: memory.creation)]

        if let conversationId = memory.conversationId, !conversationId.isEmpty {
            detailComponents.append(String(localized: "Conversation: \(conversationId)"))
        }

        detailLabel.text = detailComponents.joined(separator: " · ")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        preservesSuperviewLayoutMargins = false
        separatorInset = UIEdgeInsets.zero
        layoutMargins = UIEdgeInsets.zero
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension MemoryListController {
    func presentEditor(for memory: Memory, isNew: Bool = false) {
        let controller = TextEditorContentController()
        controller.title = String(localized: "Memory")
        controller.text = isNew ? "" : memory.content
        controller.callback = { [weak self] text in
            guard let self else { return }
            Task {
                do {
                    try await MemoryStore.shared.updateMemoryAsync(id: memory.id, newContent: text)
                    let refreshed = try await MemoryStore.shared.getAllMemoriesAsync()
                    await MainActor.run {
                        guard let self else { return }
                        self.updateDataSource(with: refreshed)
                    }
                } catch {
                    await MainActor.run {
                        guard let self else { return }
                        let errorAlert = AlertViewController(
                            title: "Error",
                            message: "Failed to update memory: \(error.localizedDescription)"
                        ) { context in
                            context.addAction(title: "OK", attribute: .accent) {
                                context.dispose()
                            }
                        }
                        self.present(errorAlert, animated: true)
                    }
                }
            }
        }

        if isNew {
            controller.cancelCallback = { [weak self] in
                guard let self else { return }
                Task {
                    do {
                        try await MemoryStore.shared.deleteMemoryAsync(id: memory.id)
                        let refreshed = try await MemoryStore.shared.getAllMemoriesAsync()
                        await MainActor.run {
                            guard let self else { return }
                            self.updateDataSource(with: refreshed)
                        }
                    } catch {
                        await MainActor.run {
                            guard let self else { return }
                            let errorAlert = AlertViewController(
                                title: "Error",
                                message: "Failed to delete memory: \(error.localizedDescription)"
                            ) { context in
                                context.addAction(title: "OK", attribute: .accent) {
                                    context.dispose()
                                }
                            }
                            self.present(errorAlert, animated: true)
                        }
                    }
                }
            }
        } else {
            controller.cancelCallback = nil
        }

        navigationController?.pushViewController(controller, animated: true)
    }

    func indexPath(for memory: Memory) -> IndexPath? {
        let displayed = currentMemories()
        guard let row = displayed.firstIndex(where: { $0.id == memory.id }) else { return nil }
        return IndexPath(row: row, section: 0)
    }

    @MainActor
    func updateDataSource(with refreshed: [Memory]) {
        memories = refreshed
        if isSearching {
            searchMemories(query: searchController.searchBar.text ?? "")
        } else {
            filteredMemories = refreshed
            tableView.reloadData()
        }
    }
}

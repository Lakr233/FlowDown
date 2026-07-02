//
//  SearchContentController.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/9/25.
//

import Combine
import UIKit

class SearchContentController: UIViewController {
    var callback: ConversationSearchController.SearchCallback

    let searchController = UISearchController(searchResultsController: nil)
    let tableView = UITableView(frame: .zero, style: .plain)
    let noResultsView = UIView()
    let emptyStateView = UIView()

    private var currentSearchToken: UUID = .init()
    var searchResults: [ConversationSearchResult] = [] {
        didSet {
            currentSearchToken = .init()
            updateNoResultsView()
            tableView.reloadData()
        }
    }

    var focusedIndexPath: IndexPath? {
        didSet {
            Logger.ui.debugFile("highlightedIndex updated: \(String(describing: focusedIndexPath))")
        }
    }

    var searchBar: UISearchBar {
        searchController.searchBar
    }

    init(callback: @escaping ConversationSearchController.SearchCallback) {
        self.callback = { _ in }
        super.init(nibName: nil, bundle: nil)
        self.callback = { [weak self] input in
            callback(input)
            self?.callback = { _ in assertionFailure() }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = String(localized: "Search Conversations")

        view.backgroundColor = .background

        searchController.searchBar.placeholder = String(localized: "Search")
        searchController.searchBar.delegate = self
        searchController.searchBar.searchBarStyle = .minimal
        searchController.searchBar.returnKeyType = .search
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.hidesNavigationBarDuringPresentation = false

        if let keyboardNavBar = searchController.searchBar as? KeyboardNavigationSearchBar {
            keyboardNavBar.keyboardNavigationDelegate = self
        }

        navigationItem.searchController = searchController
        navigationItem.preferredSearchBarPlacement = .stacked
        navigationItem.hidesSearchBarWhenScrolling = false
        definesPresentationContext = true

        tableView.keyboardDismissMode = .none

        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }
        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(SearchResultCell.self, forCellReuseIdentifier: "SearchResultCell")
        tableView.backgroundColor = .clear
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .zero
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 60

        setupNoResultsView()
        setupEmptyStateView()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        #if !targetEnvironment(macCatalyst)
            searchController.searchBar.becomeFirstResponder()
        #endif
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.searchController.searchBar.becomeFirstResponder()
        }
    }

    private let searchQueue = DispatchQueue(
        label: "SearchContentController.searchQueue",
        qos: .userInitiated,
    )

    @objc func performSearch(query: String) {
        let token = UUID()
        currentSearchToken = token
        // serial queue to handle requests so we are doing only the latest one
        searchQueue.async { [weak self] in
            guard let self, currentSearchToken == token else { return }
            let searchResults = ConversationManager.shared.searchConversations(query: query)
            Task { @MainActor [weak self] in
                guard let self, currentSearchToken == token else { return }
                self.searchResults = searchResults
            }
        }
    }

    func handleEnterKey() {
        guard !searchResults.isEmpty else { return }
        guard let selectionIndexPath = focusedIndexPath else { return }
        tableView.cellForRow(at: selectionIndexPath)?.puddingAnimate()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            self.selectResultAndDismiss(at: selectionIndexPath)
        }
    }

    func handleUpArrow() {
        guard !searchResults.isEmpty else { return }

        if var currentIndex = focusedIndexPath {
            currentIndex.row -= 1
            currentIndex.row = max(currentIndex.row, 0)
            updateHighlightedIndex(currentIndex)
        } else {
            updateHighlightedIndex(.init(row: searchResults.count - 1, section: 0))
        }
    }

    func handleDownArrow() {
        guard !searchResults.isEmpty else { return }

        if var currentIndex = focusedIndexPath {
            currentIndex.row += 1
            currentIndex.row = min(currentIndex.row, searchResults.count - 1)
            updateHighlightedIndex(currentIndex)
        } else {
            updateHighlightedIndex(.init(row: 0, section: 0))
        }
    }

    func updateHighlightedIndex(_ newIndex: IndexPath) {
        focusedIndexPath = newIndex

        let cells = tableView.visibleCells.compactMap { $0 as? SearchResultCell }
        for visibleCell in cells {
            let shouldHighlight = tableView.indexPath(for: visibleCell) == newIndex
            visibleCell.updateHighlightState(shouldHighlight)
        }

        tableView.scrollToRow(at: newIndex, at: .none, animated: true)
    }

    func selectResultAndDismiss(at indexPath: IndexPath) {
        guard indexPath.row < searchResults.count else { return }

        let result = searchResults[indexPath.row]
        let conversationId = result.conversation.id
        Logger.ui.debugFile("selectResultAndDismiss called for conversation: \(conversationId)")

        if let navController = navigationController {
            navController.dismiss(animated: true) { [weak self] in
                Logger.ui.debugFile("Search dismiss animation completed, calling callback for: \(conversationId)")
                self?.callback(conversationId)
            }
        } else {
            dismiss(animated: true) { [weak self] in
                Logger.ui.debugFile("Search dismiss animation completed, calling callback for: \(conversationId)")
                self?.callback(conversationId)
            }
        }
    }
}

//
//  ConversationSelectionView.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/3/25.
//

import Combine
import Foundation
import Storage
import UIKit

private class GroundedTableView: UITableView {
    @objc var allowsHeaderViewsToFloat: Bool {
        false
    }

    @objc var allowsFooterViewsToFloat: Bool {
        false
    }
}

class ConversationSelectionView: UIView {
    let tableView: UITableView
    let dataSource: DataSource

    var cancellables: Set<AnyCancellable> = []

    /// The selection the list last scrolled to, so that a list update showing
    /// the same selection again leaves the user's scroll position alone.
    private var lastRevealedSelection: Conversation.ID?

    typealias DataIdentifier = Conversation.ID
    typealias SectionIdentifier = Date

    typealias DataSource = UITableViewDiffableDataSource<SectionIdentifier, DataIdentifier>
    typealias Snapshot = NSDiffableDataSourceSnapshot<SectionIdentifier, DataIdentifier>

    init() {
        tableView = GroundedTableView(frame: .zero, style: .plain)
        tableView.register(Cell.self, forCellReuseIdentifier: "Cell")

        dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
            tableView.separatorColor = .clear
            let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath) as! Cell
            let conv = ConversationManager.shared.conversation(identifier: itemIdentifier)
            cell.use(conv)
            return cell
        }
        dataSource.defaultRowAnimation = .fade

        super.init(frame: .zero)

        isUserInteractionEnabled = true

        addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.separatorInset = .zero
        tableView.separatorColor = .clear
        tableView.contentInset = .zero
        tableView.allowsMultipleSelection = false
        tableView.selectionFollowsFocus = true
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.showsHorizontalScrollIndicator = false
        tableView.sectionHeaderTopPadding = 0
        tableView.sectionHeaderHeight = UITableView.automaticDimension

        updateDataSource()

        Publishers.CombineLatest(
            ConversationManager.shared.conversations,
            ChatSelection.shared.selection,
        )
        .debounce(for: .milliseconds(16), scheduler: DispatchQueue.main)
        .ensureMainThread()
        .sink { [weak self] _, selection in
            guard let self else { return }
            updateDataSource()
            let identifier = selection.identifier
            let optionDescription: String = {
                switch selection {
                case .none:
                    return "none"
                case let .conversation(_, options):
                    var components: [String] = []
                    if options.contains(.collapseSidebar) { components.append("collapseSidebar") }
                    if options.contains(.focusEditor) { components.append("focusEditor") }
                    return components.isEmpty ? "none" : components.joined(separator: ",")
                }
            }()
            Logger.ui.debugFile("ConversationSelectionView received global selection: \(identifier ?? "nil") options: \(optionDescription)")
            let selectedIndexPath = Set(tableView.indexPathsForSelectedRows ?? [])
            for index in selectedIndexPath {
                tableView.deselectRow(at: index, animated: false)
            }
            if let identifier,
               let indexPath = dataSource.indexPath(for: identifier)
            {
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                // Every list update runs this again for the same selection.
                // Only a new selection is worth scrolling to, otherwise each
                // update pulls the list back from wherever the user scrolled.
                let shouldReveal = !visible && identifier != lastRevealedSelection
                lastRevealedSelection = identifier
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: shouldReveal ? .middle : .none,
                )
            } else if dataSource.numberOfSections(in: tableView) > 0,
                      dataSource.tableView(tableView, numberOfRowsInSection: 0) > 0
            {
                let indexPath = IndexPath(row: 0, section: 0)
                let visible = tableView.indexPathsForVisibleRows?.contains(indexPath) ?? false
                tableView.selectRow(
                    at: indexPath,
                    animated: false,
                    scrollPosition: visible ? .none : .middle,
                )
                // The open conversation can leave the list without going
                // through a local delete, for example when another device
                // removes it. Move the chat to the row highlighted above, or
                // it keeps showing and saving into a conversation that no
                // longer appears anywhere.
                if let replacement = ConversationSelectionView.replacementSelection(
                    for: identifier,
                    displayed: dataSource.snapshot().itemIdentifiers,
                    isAvailable: { ConversationManager.shared.conversation(identifier: $0) != nil },
                ) {
                    ChatSelection.shared.select(replacement)
                }
            }
        }
        .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func updateDataSource() {
        let list = ConversationManager.shared.conversations.value.values
        guard !list.isEmpty else {
            _ = ConversationManager.shared.initialConversation()
            return
        }

        var snapshot = Snapshot()

        let favorited = list.filter(\.isFavorite)
        if !favorited.isEmpty {
            let favoriteSection = Date(timeIntervalSince1970: -1)
            snapshot.appendSections([favoriteSection])
            snapshot.appendItems(favorited.map(\.id), toSection: favoriteSection)
        }

        let calendar = Calendar.current

        var conversationsByDate: [Date: [Conversation.ID]] = [:]
        for item in list where !item.isFavorite {
            let dateOnly = calendar.startOfDay(for: item.creation)
            if conversationsByDate[dateOnly] == nil {
                conversationsByDate[dateOnly] = []
            }
            conversationsByDate[dateOnly]?.append(item.id)
        }

        let sortedDates = conversationsByDate.keys.sorted(by: >)

        for date in sortedDates {
            snapshot.appendSections([date])
            if let conversations = conversationsByDate[date] {
                snapshot.appendItems(conversations, toSection: date)
            }
        }
        let previousSections = dataSource.snapshot().sectionIdentifiers
        if previousSections.count == 1, sortedDates.count > 1 {
            // reload all!
            snapshot.reloadSections(sortedDates)
        }

        dataSource.apply(snapshot, animatingDifferences: true)

        Task { @MainActor [self] in
            var snapshot = dataSource.snapshot()
            let visibleRows = tableView.indexPathsForVisibleRows ?? []
            let visibleItemIdentifiers = visibleRows
                .map { dataSource.itemIdentifier(for: $0) }
                .compactMap(\.self)
            snapshot.reconfigureItems(visibleItemIdentifiers)
            dataSource.apply(snapshot, animatingDifferences: true)
        }
    }

    /// The conversation to open in place of a selection that has gone away.
    ///
    /// Returns nil when the selection should stay as it is: nothing is
    /// selected, the selected conversation still exists, or there is no
    /// existing conversation to fall back to. The fallback is the first row
    /// on display, which is the one the list highlights in that case.
    static func replacementSelection(
        for selected: Conversation.ID?,
        displayed: [Conversation.ID],
        isAvailable: (Conversation.ID) -> Bool,
    ) -> Conversation.ID? {
        guard let selected, !isAvailable(selected) else { return nil }
        guard let first = displayed.first, isAvailable(first) else { return nil }
        return first
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // detect command + 1/2/3/4 ... 9 to select conversation
        var resolved = false
        for press in presses {
            guard let key = press.key else { continue }
            let keyCode = key.charactersIgnoringModifiers
            guard keyCode.count == 1,
                  key.modifierFlags.contains(.command),
                  var digit = Int(keyCode)
            else { continue }
            digit -= 1
            guard digit >= 0, digit < dataSource.snapshot().numberOfItems else {
                continue
            }

            // now check which section we are in
            let snapshot = dataSource.snapshot()
            var sectionIndex: Int? = nil
            var sectionItemIndex: Int? = nil
            var currentCount = 0
            for (index, section) in snapshot.sectionIdentifiers.enumerated() {
                let count = snapshot.numberOfItems(inSection: section)
                if currentCount + count > digit {
                    sectionIndex = index
                    sectionItemIndex = digit - currentCount
                    break
                }
                currentCount += count
            }
            guard let sectionIndex, let sectionItemIndex else {
                assertionFailure()
                continue
            }
            let indexPath = IndexPath(item: sectionItemIndex, section: sectionIndex)
            let identifier = dataSource.itemIdentifier(for: indexPath)
            ChatSelection.shared.select(identifier)
            resolved = true
        }
        if !resolved {
            super.pressesBegan(presses, with: event)
        }
    }
}

//
//  ModelController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import Combine
import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent {
    class ModelController: UIViewController {
        enum ModelActionType {
            case local(
                verify: @MainActor () async -> Void,
                evaluate: @MainActor () async -> Void,
                openHuggingFace: @MainActor () -> Void,
                export: @MainActor () async -> Void,
                delete: @MainActor () -> Void,
            )
            case cloud(
                verify: @MainActor () async -> Void,
                evaluate: @MainActor () async -> Void,
                export: @MainActor () -> Void,
                duplicate: @MainActor () -> Void,
                delete: @MainActor () -> Void,
            )
        }

        static func makeNewChatMenuElement(
            for modelIdentifier: ModelManager.ModelIdentifier,
            controller: UIViewController?,
        ) -> [UIAction] {
            let defaultModel = ModelManager.ModelIdentifier.defaultModelForConversation
            let isDefaultModel = modelIdentifier == defaultModel

            let newChat = UIAction(
                title: String(localized: "New Chat"),
                image: UIImage(systemName: "plus.bubble"),
            ) { [weak controller] _ in
                if !isDefaultModel {
                    ModelManager.ModelIdentifier.defaultModelForConversation = modelIdentifier
                }
                let conversation = ConversationManager.shared.createNewConversation()
                ChatSelection.shared.select(conversation.id, options: [.collapseSidebar, .focusEditor])
                controller?.navigationController?.dismiss(animated: true)
            }

            if isDefaultModel {
                return [newChat]
            }

            let newChatUseOnce = UIAction(
                title: String(localized: "New Chat (Use Once)"),
                image: UIImage(systemName: "plus.bubble"),
            ) { [weak controller] _ in
                let conversation = ConversationManager.shared.createNewConversation { conv in
                    conv.update(\.modelId, to: modelIdentifier)
                }
                ChatSelection.shared.select(conversation.id, options: [.collapseSidebar, .focusEditor])
                controller?.navigationController?.dismiss(animated: true)
            }

            return [newChat, newChatUseOnce]
        }

        static func makeActionMenuElements(
            for modelIdentifier: ModelManager.ModelIdentifier,
            controller: UIViewController?,
            actionType: ModelActionType,
        ) -> [UIMenuElement] {
            let newChatActions = makeNewChatMenuElement(for: modelIdentifier, controller: controller)
            let newChatSection = UIMenu(title: "", options: [.displayInline], children: newChatActions)

            switch actionType {
            case let .local(verify, evaluate, openHuggingFace, export, delete):
                let verifyAction = UIAction(
                    title: String(localized: "Verify Model"),
                    image: UIImage(systemName: "testtube.2"),
                ) { _ in
                    Task { @MainActor in await verify() }
                }

                let evaluateAction = UIAction(
                    title: String(localized: "Evaluate"),
                    image: UIImage(systemName: "chart.bar.xaxis.ascending"),
                ) { _ in
                    Task { @MainActor in await evaluate() }
                }

                let openHuggingFaceAction = UIAction(
                    title: String(localized: "Open in Hugging Face"),
                    image: UIImage(systemName: "safari"),
                ) { _ in
                    Task { @MainActor in openHuggingFace() }
                }

                let exportAction = UIAction(
                    title: String(localized: "Export Model"),
                    image: UIImage(systemName: "square.and.arrow.up"),
                ) { _ in
                    Task { @MainActor in await export() }
                }

                let deleteAction = UIAction(
                    title: String(localized: "Delete Model"),
                    image: UIImage(systemName: "trash"),
                    attributes: [.destructive],
                ) { _ in
                    Task { @MainActor in delete() }
                }

                let verifySection = UIMenu(
                    title: "",
                    options: [.displayInline],
                    children: [verifyAction, evaluateAction]
                )
                let utilitySection = UIMenu(
                    title: "",
                    options: [.displayInline],
                    children: [openHuggingFaceAction, exportAction]
                )
                let deleteSection = UIMenu(title: "", options: [.displayInline], children: [deleteAction])

                return [newChatSection, verifySection, utilitySection, deleteSection]

            case let .cloud(verify, evaluate, export, duplicate, delete):
                let verifyAction = UIAction(
                    title: String(localized: "Verify Model"),
                    image: UIImage(systemName: "testtube.2"),
                ) { _ in
                    Task { @MainActor in await verify() }
                }
                let evaluateAction = UIAction(
                    title: String(localized: "Evaluate"),
                    image: UIImage(systemName: "chart.bar.xaxis.ascending"),
                ) { _ in
                    Task { @MainActor in await evaluate() }
                }
                let exportAction = UIAction(
                    title: String(localized: "Export Model"),
                    image: UIImage(systemName: "square.and.arrow.up"),
                ) { _ in
                    Task { @MainActor in export() }
                }

                let duplicateAction = UIAction(
                    title: String(localized: "Duplicate"),
                    image: UIImage(systemName: "doc.on.doc"),
                ) { _ in
                    Task { @MainActor in duplicate() }
                }

                let deleteAction = UIAction(
                    title: String(localized: "Delete Model"),
                    image: UIImage(systemName: "trash"),
                    attributes: [.destructive],
                ) { _ in
                    Task { @MainActor in delete() }
                }

                let verifySection = UIMenu(
                    title: "",
                    options: [.displayInline],
                    children: [verifyAction, evaluateAction]
                )
                let exportSection = UIMenu(
                    title: "",
                    options: [.displayInline],
                    children: [exportAction, duplicateAction]
                )
                let deleteSection = UIMenu(title: "", options: [.displayInline], children: [deleteAction])

                return [newChatSection, verifySection, exportSection, deleteSection]
            }
        }

        let tableView: UITableView
        let dataSource: DataSource

        enum ModelType: String {
            case local
            case cloud

            var title: String {
                switch self {
                case .local: String(localized: "Local Model")
                case .cloud: String(localized: "Cloud Model")
                }
            }
        }

        struct ModelViewModel: Hashable {
            let type: ModelType
            let identifier: String
        }

        typealias DataSource = UITableViewDiffableDataSource<ModelType, ModelViewModel>
        typealias Snapshot = NSDiffableDataSourceSnapshot<ModelType, ModelViewModel>

        var cancellable: Set<AnyCancellable> = []

        @TypedStorage(key: "ModelController.showCloudModel", defaultValue: true)
        var showCloudModels {
            didSet { updateDataSource() }
        }

        @TypedStorage(key: "ModelController.showLocalModel", defaultValue: true)
        var showLocalModels {
            didSet { updateDataSource() }
        }

        init() {
            tableView = UITableView(frame: .zero, style: .plain)
            dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
                let cell = tableView.dequeueReusableCell(withIdentifier: "ModelCell", for: indexPath) as! ModelCell
                switch itemIdentifier.type {
                case .local:
                    if let model = ModelManager.shared.localModel(identifier: itemIdentifier.identifier) {
                        let name = model.modelDisplayName
                        let tags = model.tags
                        cell.update(type: .local, name: name, descriptions: tags)
                    }
                case .cloud:
                    if let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier) {
                        let name = model.modelDisplayName
                        let tags = model.tags
                        cell.update(type: .cloud, name: name, descriptions: tags)
                    }
                }
                return cell
            }
            tableView.register(ModelCell.self, forCellReuseIdentifier: "ModelCell")

            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Model Management")

            Publishers.CombineLatest(
                ModelManager.shared.localModels.removeDuplicates(),
                ModelManager.shared.cloudModels.removeDuplicates(),
            )
            .ensureMainThread()
            .sink { [weak self] _ in self?.updateDataSource() }
            .store(in: &cancellable)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        deinit {
            cancellable.forEach { $0.cancel() }
            cancellable.removeAll()
        }

        lazy var addItem: UIBarButtonItem = .init(
            image: .init(systemName: "plus"),
            menu: UIMenu(children: createAddModelMenuItems()),
        )

        lazy var filterBarItem: UIBarButtonItem = {
            let deferredMenu = UIDeferredMenuElement.uncached { [weak self] completion in
                guard let self else {
                    completion([])
                    return
                }
                completion(createFilterMenuItems())
            }
            return UIBarButtonItem(
                image: .init(systemName: "line.3.horizontal.decrease.circle"),
                menu: UIMenu(title: String(localized: "Filter Options"), children: [deferredMenu]),
            )
        }()

        var searchKey: String {
            navigationItem.searchController?.searchBar.text ?? ""
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
            tableView.separatorStyle = .singleLine
            tableView.separatorInset = .zero
            tableView.backgroundColor = .clear
            tableView.delegate = self
            tableView.allowsMultipleSelection = false
            tableView.dragDelegate = self
            tableView.dragInteractionEnabled = true
            dataSource.defaultRowAnimation = .fade
            view.addSubview(tableView)
            tableView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            navigationItem.rightBarButtonItems = [
                addItem,
                filterBarItem,
            ]

            let searchController = UISearchController(searchResultsController: nil)
            searchController.delegate = self
            searchController.searchBar.placeholder = String(localized: "Search Model")
            searchController.searchBar.autocapitalizationType = .none
            searchController.searchBar.autocorrectionType = .no
            searchController.searchBar.delegate = self
            navigationItem.searchController = searchController
            navigationItem.preferredSearchBarPlacement = .stacked
            navigationItem.hidesSearchBarWhenScrolling = false
            navigationItem.searchController?.obscuresBackgroundDuringPresentation = false
            navigationItem.searchController?.hidesNavigationBarDuringPresentation = false
        }

        func updateDataSource() {
            var snapshot = Snapshot()
            let localModels = ModelManager.shared.localModels.value.filter {
                searchKey.isEmpty || $0.model_identifier.localizedCaseInsensitiveContains(searchKey)
            }
            if !localModels.isEmpty, showLocalModels {
                snapshot.appendSections([.local])
                snapshot.appendItems(
                    localModels.map { ModelViewModel(type: .local, identifier: $0.id) },
                    toSection: .local
                )
            }
            let remoteModels = ModelManager.shared.cloudModels.value.filter {
                searchKey.isEmpty || $0.model_identifier.localizedCaseInsensitiveContains(searchKey)
            }
            if !remoteModels.isEmpty, showCloudModels {
                snapshot.appendSections([.cloud])
                snapshot.appendItems(
                    remoteModels.map { ModelViewModel(type: .cloud, identifier: $0.id) },
                    toSection: .cloud
                )
            }
            dataSource.apply(snapshot, animatingDifferences: true)
            updateVisibleItems()
            updateFilterIcon()
        }

        func updateVisibleItems() {
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(tableView.indexPathsForVisibleRows?.compactMap {
                dataSource.itemIdentifier(for: $0)
            } ?? [])
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        func updateFilterIcon() {
            if showCloudModels, showLocalModels {
                filterBarItem.image = .init(systemName: "line.3.horizontal.decrease.circle")
            } else {
                filterBarItem.image = .init(systemName: "line.3.horizontal.decrease.circle.fill")
            }
        }
    }
}

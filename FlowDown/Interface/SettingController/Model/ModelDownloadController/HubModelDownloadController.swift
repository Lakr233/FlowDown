//
//  HubModelDownloadController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/26/25.
//

import AlertController
import BetterCodable
import ConfigurableKit
import Foundation
import UIKit

class HubModelDownloadController: UIViewController {
    let activityIndicator = UIActivityIndicatorView(style: .medium)

    var searchTask: URLSessionDataTask?
    var searchSession = UUID()

    var searchResults: [RemoteModel] = []
    enum Section: String { case main }
    typealias DataSource = UITableViewDiffableDataSource<Section, RemoteModel>
    typealias Snapshot = NSDiffableDataSourceSnapshot<Section, RemoteModel>

    let tableView: UITableView
    let dataSource: DataSource

    @TypedStorage(key: "ModelDownloadController.anchorToVerifiedAuthorMLX", defaultValue: true)
    var anchorToVerifiedAuthorMLX {
        didSet { updateDataSource() }
    }

    @TypedStorage(key: "ModelDownloadController.anchorToTextGenerationModels", defaultValue: true)
    var anchorToTextGenerationModels {
        didSet { updateDataSource() }
    }

    init() {
        tableView = .init(frame: .zero, style: .plain)
        dataSource = .init(tableView: tableView) { tableView, indexPath, itemIdentifier in
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! Cell
            cell.use(model: itemIdentifier)
            return cell
        }
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Download Model")
        dataSource.defaultRowAnimation = .fade
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        defer { updateDataSource() }

        view.backgroundColor = .background
        view.addSubview(tableView)

        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .zero
        tableView.delegate = self
        tableView.dataSource = dataSource
        tableView.register(Cell.self, forCellReuseIdentifier: "cell")
        tableView.snp.makeConstraints { make in
            make.left.top.right.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(view.keyboardLayoutGuide.snp.top)
        }

        // Only add the spinner when it's animating to avoid empty glass artifacts
        updateRightBarButtons()
        activityIndicator.stopAnimating()

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

    private func updateRightBarButtons() {
        let deferredMenu = UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else {
                completion([])
                return
            }
            completion(createFilterMenuItems())
        }
        let filterItem = UIBarButtonItem(
            image: .init(systemName: "ellipsis"),
            menu: UIMenu(children: [deferredMenu]),
        )

        var items: [UIBarButtonItem] = [filterItem]
        if activityIndicator.isAnimating {
            items.append(.init(customView: activityIndicator))
        }
        navigationItem.rightBarButtonItems = items
    }

    private var isFirstAppear = true
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isFirstAppear else { return }
        isFirstAppear = false
        let warning = AlertViewController(
            title: "Warning",
            message: "Features provided by this page are suitable for users who have experience deploying large language models. Running models that exceed the resources of the device may cause the application or system to crash. Please proceed with caution.\n\nReady to dive in? Select a model to see its size and details.",
        ) { [weak self] context in
            context.addAction(title: "Cancel") { [weak self] in
                context.dispose { [weak self] in
                    self?.navigationController?.popViewController(animated: true)
                }
            }
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose {}
            }
        }
        present(warning, animated: true)
    }

    func updateDataSource() {
        let searchKey = navigationItem.searchController?.searchBar.text ?? ""
        activityIndicator.startAnimating()
        updateRightBarButtons()
        let session = UUID()
        searchSession = session
        fetchModel(keyword: searchKey) { [weak self] models in
            guard self?.searchSession == session else { return }
            var snapshot = Snapshot()
            snapshot.appendSections([.main])
            snapshot.appendItems(models)
            self?.dataSource.apply(snapshot, animatingDifferences: true)
            self?.activityIndicator.stopAnimating()
            self?.updateRightBarButtons()
        }
    }

    func createFilterMenuItems() -> [UIMenuElement] {
        [
            UIMenu(
                title: String(localized: "Filter Options"),
                options: [.displayInline],
                children: [
                    UIAction(
                        title: String(localized: "Text Model Only"),
                        image: UIImage(systemName: "text.append"),
                        state: anchorToTextGenerationModels ? .on : .off,
                    ) { [weak self] _ in
                        self?.anchorToTextGenerationModels.toggle()
                    },
                    UIAction(
                        title: String(localized: "Verified Model Only"),
                        image: UIImage(systemName: "rosette"),
                        state: anchorToVerifiedAuthorMLX ? .on : .off,
                    ) { [weak self] _ in
                        self?.anchorToVerifiedAuthorMLX.toggle()
                    },
                ],
            ),
        ]
    }
}

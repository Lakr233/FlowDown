//
//  MCPController.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//

import AlertController
import Combine
import ConfigurableKit
import Storage
import UIKit
import UniformTypeIdentifiers

private let utType = UTType(filenameExtension: "fdmcp")?.identifier ?? "wiki.qaq.fdmcp"

extension SettingController.SettingContent {
    class MCPController: UIViewController {
        let tableView: UITableView
        let dataSource: DataSource

        enum TableViewSection: String {
            case main
        }

        typealias DataSource = UITableViewDiffableDataSource<TableViewSection, ModelContextServer.ID>
        typealias Snapshot = NSDiffableDataSourceSnapshot<TableViewSection, ModelContextServer.ID>

        var cancellable: Set<AnyCancellable> = []

        init() {
            tableView = UITableView(frame: .zero, style: .plain)
            dataSource = .init(tableView: tableView, cellProvider: Self.cellProvider)

            super.init(nibName: nil, bundle: nil)
            title = String(localized: "MCP Servers")

            tableView.register(
                MCPServerCell.self,
                forCellReuseIdentifier: NSStringFromClass(MCPServerCell.self),
            )
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        deinit {
            cancellable.forEach { $0.cancel() }
            cancellable.removeAll()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background

            navigationItem.rightBarButtonItem = UIBarButtonItem(
                image: UIImage(systemName: "plus"),
                menu: UIMenu(children: createAddClientMenuItems()),
            )

            dataSource.defaultRowAnimation = .fade
            tableView.delegate = self
            tableView.dragDelegate = self
            tableView.dropDelegate = self
            tableView.dragInteractionEnabled = true
            tableView.separatorStyle = .singleLine
            tableView.separatorColor = SeparatorView.color
            tableView.backgroundColor = .clear
            tableView.backgroundView = nil
            tableView.alwaysBounceVertical = true
            tableView.contentInset = .zero
            tableView.scrollIndicatorInsets = .zero
            view.addSubview(tableView)
            tableView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }

            MCPService.shared.servers
                .ensureMainThread()
                .sink { [weak self] clients in
                    self?.updateSnapshot(clients)
                }
                .store(in: &cancellable)
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            MCPService.shared.updateFromDatabase()
            Task { @MainActor in
                self.tableView.reloadData()
            }
        }

        func updateSnapshot(_ clients: [ModelContextServer]) {
            var snapshot = Snapshot()
            snapshot.appendSections([.main])
            snapshot.appendItems(clients.map(\.id), toSection: .main)
            dataSource.apply(snapshot, animatingDifferences: true)
        }

        static let cellProvider: DataSource.CellProvider = { tableView, indexPath, clientId in
            let cell = tableView.dequeueReusableCell(
                withIdentifier: NSStringFromClass(MCPServerCell.self),
                for: indexPath,
            )
            cell.contentView.isUserInteractionEnabled = false
            if let cell = cell as? MCPServerCell {
                cell.configure(with: clientId)
            }
            return cell
        }
    }
}

extension SettingController.SettingContent.MCPController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let clientId = dataSource.itemIdentifier(for: indexPath) else { return }
        let controller = MCPEditorController(clientId: clientId)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let clientId = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(
            style: .destructive,
            title: "Delete",
        ) { _, _, completion in
            MCPService.shared.remove(clientId)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard let clientId = dataSource.itemIdentifier(for: indexPath),
              let server = MCPService.shared.server(with: clientId) else { return nil }

        let menu = UIMenu(children: [
            UIMenu(options: [.displayInline], children: [
                UIAction(
                    title: server.isEnabled ? String(localized: "Disable") : String(localized: "Enable"),
                    image: UIImage(systemName: server.isEnabled ? "pause.circle" : "play.circle"),
                ) { _ in
                    MCPService.shared.edit(identifier: clientId) {
                        $0.update(\.isEnabled, to: !$0.isEnabled)
                    }
                    self.tableView.reloadData()
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Export Server"), image: UIImage(systemName: "square.and.arrow.up")) { _ in
                    self.exportServer(clientId)
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    MCPService.shared.remove(clientId)
                },
            ]),
        ])

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            menu
        }
    }
}

extension SettingController.SettingContent.MCPController: UIDocumentPickerDelegate {
    func doImport(urls: [URL]) {
        guard !urls.isEmpty else { return }

        Indicator.progress(
            title: "Importing MCP Servers",
            controller: self,
        ) { completionHandler in
            var success = 0
            var failure: [Error] = .init()

            for url in urls {
                do {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    try await MainActor.run {
                        _ = try MCPService.shared.importServer(from: data)
                    }
                    success += 1
                } catch {
                    failure.append(error)
                }
            }

            if success == 0, let firstError = failure.first {
                throw firstError
            }

            await completionHandler {
                if !failure.isEmpty {
                    let alert = AlertViewController(
                        title: "Import Failed",
                        message: "\(success) servers imported successfully, \(failure.count) failed.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self.present(alert, animated: true)
                } else {
                    Indicator.present(
                        title: "Imported \(success) servers.",
                        preset: .done,
                        referencingView: self.view,
                    )
                }
            }
        }
    }

    func documentPicker(
        _: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL],
    ) {
        doImport(urls: urls)
    }
}

extension SettingController.SettingContent.MCPController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let serverId = dataSource.itemIdentifier(for: indexPath),
              let server = MCPService.shared.server(with: serverId)
        else {
            return []
        }

        let itemProvider = NSItemProvider()

        do {
            let data = try MCPService.shared.exportServerData(server)
            itemProvider.registerDataRepresentation(
                forTypeIdentifier: utType,
                visibility: .all,
            ) { completion in
                completion(data, nil)
                return nil
            }

            // Set suggested name based on server host or name
            let serverName = if let url = URL(string: server.endpoint), let host = url.host {
                host
            } else if !server.name.isEmpty {
                server.name
            } else {
                "MCPServer"
            }
            itemProvider.suggestedName = "\(serverName.sanitizedFileName).fdmcp"
        } catch {
            Logger.app.errorFile("failed to encode MCP server for drag: \(error)")
        }

        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = serverId
        return [dragItem]
    }

    func tableView(
        _: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath _: IndexPath?
    ) -> UITableViewDropProposal {
        // MCPService keeps no order, and importing a row dragged from inside the
        // app (this list or one in another window) would duplicate it.
        guard session.localDragSession == nil else {
            return UITableViewDropProposal(operation: .cancel)
        }
        if session.hasItemsConforming(toTypeIdentifiers: [utType]) {
            return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
        }
        return UITableViewDropProposal(operation: .cancel)
    }

    func tableView(_: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard coordinator.session.localDragSession == nil else { return }
        for item in coordinator.items {
            let itemProvider = item.dragItem.itemProvider
            if itemProvider.hasItemConformingToTypeIdentifier(utType) {
                itemProvider.loadDataRepresentation(forTypeIdentifier: utType) { data, error in
                    guard let data, error == nil else { return }

                    Task { @MainActor in
                        do {
                            _ = try MCPService.shared.importServer(from: data)
                        } catch {
                            Logger.app.errorFile("failed to import dropped MCP server: \(error)")
                        }
                    }
                }
            }
        }
    }
}

extension SettingController.SettingContent.MCPController {
    func exportServer(_ serverId: ModelContextServer.ID) {
        guard let server = MCPService.shared.server(with: serverId) else { return }

        let tempFileDir = disposableResourcesDir
            .appendingPathComponent(UUID().uuidString)
        let serverName = if let url = URL(string: server.endpoint), let host = url.host {
            host
        } else if !server.name.isEmpty {
            server.name
        } else {
            "MCPServer"
        }
        let tempFile = tempFileDir
            .appendingPathComponent("Export-\(serverName.sanitizedFileName)")
            .appendingPathExtension("fdmcp")
        try? FileManager.default.createDirectory(at: tempFileDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)

        do {
            let data = try MCPService.shared.exportServerData(server)
            try data.write(to: tempFile, options: .atomic)

            DisposableExporter(deletableItem: tempFile, title: "Export MCP Server").run(anchor: view)
        } catch {
            Logger.app.errorFile("failed to export MCP server: \(error)")
        }
    }
}

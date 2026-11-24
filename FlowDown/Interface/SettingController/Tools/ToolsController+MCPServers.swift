//
//  ToolsController+MCPServers.swift
//  FlowDown
//
//  Created by LiBr on 6/30/25.
//

import AlertController
import ConfigurableKit
import Storage
import UIKit
import UniformTypeIdentifiers

private let utType = UTType(filenameExtension: "fdmcp")?.identifier ?? "wiki.qaq.fdmcp"

extension SettingController.SettingContent.ToolsController {
    enum MCPListSection: Hashable {
        case main
    }

    enum MCPListItem: Hashable {
        case server(ModelContextServer.ID)
        /// The only row while no server has been added.
        case addServer
    }

    typealias MCPSnapshot = NSDiffableDataSourceSnapshot<MCPListSection, MCPListItem>

    /// Server rows in the order MCPService keeps them, or the add row alone.
    static func mcpListItems(for serverIDs: [ModelContextServer.ID]) -> [MCPListItem] {
        serverIDs.isEmpty ? [.addServer] : serverIDs.map { .server($0) }
    }

    /// A table as tall as its rows, so it can sit in the page's stack.
    final class MCPServerListView: UITableView {
        override var contentSize: CGSize {
            didSet {
                guard oldValue.height != contentSize.height else { return }
                invalidateIntrinsicContentSize()
            }
        }

        override var intrinsicContentSize: CGSize {
            .init(width: UIView.noIntrinsicMetric, height: contentSize.height)
        }
    }

    final class MCPDataSource: UITableViewDiffableDataSource<MCPListSection, MCPListItem> {
        /// Only server rows swipe; the add row stays put.
        override func tableView(_: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
            if case .server = itemIdentifier(for: indexPath) { return true }
            return false
        }
    }

    func makeMCPDataSource() -> MCPDataSource {
        let dataSource = MCPDataSource(tableView: mcpTableView) { [weak self] tableView, indexPath, item in
            switch item {
            case let .server(clientId):
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: NSStringFromClass(MCPServerCell.self),
                    for: indexPath,
                )
                cell.contentView.isUserInteractionEnabled = false
                if let cell = cell as? MCPServerCell {
                    cell.configure(with: clientId)
                }
                return cell
            case .addServer:
                let cell = tableView.dequeueReusableCell(
                    withIdentifier: NSStringFromClass(AddMCPServerCell.self),
                    for: indexPath,
                )
                if let cell = cell as? AddMCPServerCell, let self {
                    cell.button.menu = UIMenu(children: self.createAddClientMenuItems())
                }
                return cell
            }
        }
        dataSource.defaultRowAnimation = .fade
        return dataSource
    }

    func configureMCPTableView() {
        let tableView = mcpTableView
        tableView.register(MCPServerCell.self, forCellReuseIdentifier: NSStringFromClass(MCPServerCell.self))
        tableView.register(AddMCPServerCell.self, forCellReuseIdentifier: NSStringFromClass(AddMCPServerCell.self))
        tableView.isScrollEnabled = false
        tableView.scrollsToTop = false
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.backgroundColor = .clear
        tableView.backgroundView = nil
        tableView.separatorStyle = .none
        tableView.cellLayoutMarginsFollowReadableWidth = false
        tableView.sectionHeaderTopPadding = 0
        // Rows size themselves; a zero estimate would turn self-sizing off.
        // The table never scrolls and is as tall as its content, so every row
        // is laid out and measured, and the content size settles on the real heights.
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = 96
        tableView.delegate = self
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        _ = mcpDataSource
        applyMCPServers([])
    }

    func applyMCPServers(_ serverIDs: [ModelContextServer.ID]) {
        let current = Set(mcpDataSource.snapshot().itemIdentifiers)
        var snapshot = MCPSnapshot()
        snapshot.appendSections([.main])
        snapshot.appendItems(Self.mcpListItems(for: serverIDs), toSection: .main)
        // Rows that stay are refreshed in place, as a server's name or state may have changed.
        snapshot.reconfigureItems(snapshot.itemIdentifiers.filter { current.contains($0) })

        let animated = mcpTableView.window != nil
        mcpDataSource.apply(snapshot, animatingDifferences: animated)
        guard animated else { return }
        // Rows below follow the table's new height while removed rows fade out.
        UIView.animate(withDuration: 0.3, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) {
            self.view.layoutIfNeeded()
        }
    }

    func confirmDeleteServer(_ clientId: ModelContextServer.ID) {
        guard let server = MCPService.shared.server(with: clientId) else { return }
        let name = server.displayName
        presentDeleteConfirmation(
            title: "Delete “\(name)”?",
            message: "This server's settings and sign-in will be deleted. This action cannot be undone.",
        ) {
            MCPService.shared.remove(clientId)
        }
    }
}

extension SettingController.SettingContent.ToolsController {
    /// The row shown while no server has been added; tapping it opens the
    /// same menu as the navigation bar's plus button.
    final class AddMCPServerCell: UITableViewCell {
        let rowView = ConfigurableView()
        let button = UIButton(type: .custom)

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            separatorInset = .zero
            selectionStyle = .none
            backgroundColor = .clear

            rowView.configure(icon: UIImage(systemName: "plus.circle"))
            rowView.configure(title: "Add MCP Server")
            rowView.iconView.tintColor = .accent
            rowView.titleLabel.textColor = .accent
            rowView.descriptionLabel.isHidden = true

            let margin = AutoLayoutMarginView(rowView)
            margin.isUserInteractionEnabled = false
            margin.accessibilityElementsHidden = true
            let separator = SeparatorView()
            contentView.addSubview(margin)
            contentView.addSubview(separator)
            contentView.addSubview(button)
            margin.snp.makeConstraints { make in
                make.top.leading.trailing.equalToSuperview()
            }
            separator.snp.makeConstraints { make in
                make.top.equalTo(margin.snp.bottom)
                make.leading.trailing.bottom.equalToSuperview()
                make.height.equalTo(1)
            }
            button.snp.makeConstraints { make in
                make.edges.equalTo(margin)
            }

            button.showsMenuAsPrimaryAction = true
            button.accessibilityLabel = String(localized: "Add MCP Server")
            button.accessibilityTraits = .button
            button.addTarget(self, action: #selector(updateHighlight), for: .allTouchEvents)
            isAccessibilityElement = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        @objc private func updateHighlight() {
            let highlighted = button.isHighlighted
            UIView.animate(withDuration: 0.1, delay: 0, options: .curveEaseOut) {
                self.rowView.alpha = highlighted ? 0.5 : 1
            }
        }
    }
}

extension SettingController.SettingContent.ToolsController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard case let .server(clientId) = mcpDataSource.itemIdentifier(for: indexPath) else { return }
        let controller = MCPEditorController(clientId: clientId)
        navigationController?.pushViewController(controller, animated: true)
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        guard case let .server(clientId) = mcpDataSource.itemIdentifier(for: indexPath) else { return nil }
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete"),
        ) { [weak self] _, _, completion in
            // The row slides back; it leaves the list only once the deletion is confirmed.
            completion(false)
            self?.confirmDeleteServer(clientId)
        }
        delete.image = UIImage(systemName: "trash")
        let configuration = UISwipeActionsConfiguration(actions: [delete])
        configuration.performsFirstActionWithFullSwipe = false
        return configuration
    }

    func tableView(
        _: UITableView,
        leadingSwipeActionsConfigurationForRowAt _: IndexPath,
    ) -> UISwipeActionsConfiguration? {
        nil
    }

    func tableView(
        _: UITableView,
        contextMenuConfigurationForRowAt indexPath: IndexPath,
        point _: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard case let .server(clientId) = mcpDataSource.itemIdentifier(for: indexPath),
              let server = MCPService.shared.server(with: clientId) else { return nil }

        var signIn: [UIMenuElement] = []
        if MCPService.shared.authorizationState(for: clientId).needsSignIn {
            signIn.append(
                UIAction(title: String(localized: "Sign In"), image: UIImage(systemName: "person.badge.key")) { [weak self] _ in
                    guard let self else { return }
                    MCPSignInFlow.signIn(serverID: clientId, from: self)
                },
            )
        }

        let menu = UIMenu(children: [
            UIMenu(options: [.displayInline], children: signIn + [
                UIAction(
                    title: server.isEnabled ? String(localized: "Disable") : String(localized: "Enable"),
                    image: UIImage(systemName: server.isEnabled ? "pause.circle" : "play.circle"),
                ) { _ in
                    MCPService.shared.edit(identifier: clientId) {
                        $0.update(\.isEnabled, to: !$0.isEnabled)
                    }
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Export Server"), image: UIImage(systemName: "square.and.arrow.up")) { [weak self] _ in
                    self?.exportServer(clientId)
                },
            ]),
            UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { [weak self] _ in
                    self?.confirmDeleteServer(clientId)
                },
            ]),
        ])

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            menu
        }
    }
}

extension SettingController.SettingContent.ToolsController: UIDocumentPickerDelegate {
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

extension SettingController.SettingContent.ToolsController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard case let .server(serverId) = mcpDataSource.itemIdentifier(for: indexPath),
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
        withDestinationIndexPath _: IndexPath?,
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

extension SettingController.SettingContent.ToolsController {
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

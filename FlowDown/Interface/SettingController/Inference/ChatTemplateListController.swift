//
//  ChatTemplateListController.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import AlertController
import Combine
import ConfigurableKit
import Foundation
import Storage
import UIKit
import UniformTypeIdentifiers

private let fdTemplateUTType = UTType(filenameExtension: "fdtemplate") ?? .data
private let fdTemplateTypeIdentifier = fdTemplateUTType.identifier

class ChatTemplateListController: UIViewController {
    private var cancellables = Set<AnyCancellable>()

    let tableView = UITableView(frame: .zero, style: .plain)

    enum Section {
        case main
    }

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    lazy var dataSource = UITableViewDiffableDataSource<
        Section,
        ChatTemplate.ID,
    >(tableView: tableView) { tableView, _, itemIdentifier in
        let cell = tableView.dequeueReusableCell(
            withIdentifier: "Cell",
        ) as! Cell
        cell.load(itemIdentifier)
        return cell
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.addSubview(tableView)
        tableView.delegate = self
        tableView.dataSource = dataSource
        tableView.dragDelegate = self
        tableView.dropDelegate = self
        tableView.dragInteractionEnabled = true
        tableView.separatorStyle = .singleLine
        tableView.separatorInset = .zero
        tableView.backgroundColor = .clear
        tableView.allowsMultipleSelection = false
        dataSource.defaultRowAnimation = .fade
        tableView.register(
            Cell.self,
            forCellReuseIdentifier: "Cell",
        )
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "plus"),
            menu: UIMenu(children: createAddTemplateMenuItems()),
        )

        ChatTemplateManager.shared.$templates
            .dropFirst()
            .ensureMainThread()
            .sink { [weak self] templates in
                guard let self else { return }
                reload(items: .init(templates.keys), animated: true)
            }
            .store(in: &cancellables)
        reload(items: .init(ChatTemplateManager.shared.templates.keys), animated: false)
    }

    func reload(items: [ChatTemplate.ID], animated: Bool) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, ChatTemplate.ID>()
        snapshot.appendSections([.main])
        snapshot.appendItems(items)
        dataSource.apply(snapshot, animatingDifferences: animated)
        Task { @MainActor [self] in
            var snapshot = dataSource.snapshot()
            snapshot.reconfigureItems(tableView.indexPathsForVisibleRows?.compactMap {
                dataSource.itemIdentifier(for: $0)
            } ?? [])
            dataSource.apply(snapshot, animatingDifferences: animated)
        }
    }

    func createAddTemplateMenuItems() -> [UIMenuElement] {
        [
            UIMenu(title: String(localized: "Chat Template"), options: [.displayInline], children: [
                UIAction(title: String(localized: "Create Template"), image: UIImage(systemName: "plus")) { [weak self] _ in
                    var template = ChatTemplate()
                    template.name = String(localized: "Template \(ChatTemplateManager.shared.templates.count + 1)")
                    ChatTemplateManager.shared.addTemplate(template)

                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        let controller = ChatTemplateEditorController(templateIdentifier: template.id)
                        navigationController?.pushViewController(controller, animated: true)
                    }
                },
                UIMenu(title: String(localized: "Import"), options: [.displayInline], children: [
                    UIAction(title: String(localized: "Import from File"), image: UIImage(systemName: "doc")) { [weak self] _ in
                        self?.presentDocumentPicker()
                    },
                ]),
            ]),
        ]
    }

    func presentDocumentPicker() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            fdTemplateUTType,
        ])
        picker.delegate = self
        picker.allowsMultipleSelection = true
        present(picker, animated: true)
    }
}

extension ChatTemplateListController: UITableViewDelegate {
    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        let delete = UIContextualAction(
            style: .destructive,
            title: "Delete",
        ) { _, _, completion in
            guard let template = ChatTemplateManager.shared.template(for: itemIdentifier) else {
                assertionFailure()
                completion(false)
                return
            }
            assert(template.id == itemIdentifier)
            ChatTemplateManager.shared.remove(for: template.id)
            completion(true)
        }
        delete.image = UIImage(systemName: "trash")
        return UISwipeActionsConfiguration(actions: [delete])
    }
}

extension ChatTemplateListController {
    class Cell: UITableViewCell, UIContextMenuInteractionDelegate {
        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            commonInit()
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            commonInit()
        }

        var identifier: ChatTemplate.ID?
        lazy var view = ConfigurablePageView {
            guard let identifier = self.identifier else { return nil }
            return ChatTemplateEditorController(templateIdentifier: identifier)
        }

        func commonInit() {
            selectionStyle = .none
            contentView.addSubview(view)
            view.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(20)
            }
            view.descriptionLabel.numberOfLines = 1
            view.descriptionLabel.lineBreakMode = .byTruncatingTail
            contentView.addInteraction(UIContextMenuInteraction(delegate: self))
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            identifier = nil
        }

        func load(_ template: ChatTemplate) {
            if let image = UIImage(data: template.avatar) {
                view.configure(icon: image)
            } else {
                view.configure(icon: UIImage(systemName: "person.crop.circle.fill"))
            }
            view.configure(title: "\(template.name)")
            view.configure(description: "\(template.prompt)")
        }

        func load(_ itemIdentifier: ChatTemplate.ID) {
            identifier = itemIdentifier
            if let template = ChatTemplateManager.shared.template(for: itemIdentifier) {
                load(template)
            } else {
                prepareForReuse()
            }
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            guard let identifier else { return nil }
            let menu = UIMenu(options: [.displayInline], children: [
                UIAction(title: String(localized: "Delete"), image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                    ChatTemplateManager.shared.remove(for: identifier)
                },
            ])
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
                menu
            }
        }
    }
}

extension ChatTemplateListController: UIDocumentPickerDelegate {
    func documentPicker(
        _: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL],
    ) {
        guard !urls.isEmpty else { return }

        Indicator.progress(
            title: "Importing Templates",
            controller: self,
        ) { completionHandler in
            var success = 0
            var failure: [Error] = .init()

            for url in urls {
                do {
                    _ = url.startAccessingSecurityScopedResource()
                    defer { url.stopAccessingSecurityScopedResource() }
                    let data = try Data(contentsOf: url)
                    _ = try ChatTemplateManager.shared.importTemplate(from: data)
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
                        message: "\(success) templates imported successfully, \(failure.count) failed.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) {
                            context.dispose()
                        }
                    }
                    self.present(alert, animated: true)
                } else {
                    Indicator.present(
                        title: "Imported \(success) templates.",
                        preset: .done,
                        referencingView: self.view,
                    )
                }
            }
        }
    }
}

extension ChatTemplateListController: UITableViewDragDelegate, UITableViewDropDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
              let template = ChatTemplateManager.shared.template(for: itemIdentifier)
        else {
            return []
        }

        let itemProvider = NSItemProvider()

        do {
            let data = try ChatTemplateManager.shared.exportTemplateData(template)
            itemProvider.registerDataRepresentation(
                forTypeIdentifier: fdTemplateTypeIdentifier,
                visibility: .all,
            ) { completion in
                completion(data, nil)
                return nil
            }
            itemProvider.suggestedName = "\(template.name).fdtemplate"
        } catch {
            Logger.app.errorFile("failed to encode template for drag: \(error)")
        }

        let dragItem = UIDragItem(itemProvider: itemProvider)
        dragItem.localObject = itemIdentifier
        return [dragItem]
    }

    func tableView(_: UITableView, canMoveRowAt _: IndexPath) -> Bool {
        true
    }

    func tableView(_: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        if sourceIndexPath == destinationIndexPath { return }
        guard let sourceItem = dataSource.itemIdentifier(for: sourceIndexPath) else { return }

        var snapshot = dataSource.snapshot()
        if sourceIndexPath.row < destinationIndexPath.row {
            if let destinationItem = dataSource.itemIdentifier(
                for: IndexPath(row: destinationIndexPath.row, section: 0),
            ) {
                guard sourceItem != destinationItem else { return }
                snapshot.moveItem(sourceItem, afterItem: destinationItem)
            }
        } else {
            if let destinationItem = dataSource.itemIdentifier(for: destinationIndexPath) {
                guard sourceItem != destinationItem else { return }
                snapshot.moveItem(sourceItem, beforeItem: destinationItem)
            }
        }

        dataSource.apply(snapshot, animatingDifferences: false)

        // 更新 ChatTemplateManager 中的顺序
        let newOrder = dataSource.snapshot().itemIdentifiers(inSection: .main)
        ChatTemplateManager.shared.reorderTemplates(newOrder)
    }

    func tableView(
        _: UITableView,
        dropSessionDidUpdate session: UIDropSession,
        withDestinationIndexPath _: IndexPath?
    ) -> UITableViewDropProposal {
        if session.localDragSession != nil {
            return UITableViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        } else if session.hasItemsConforming(toTypeIdentifiers: [fdTemplateTypeIdentifier]) {
            return UITableViewDropProposal(operation: .copy, intent: .insertAtDestinationIndexPath)
        }
        return UITableViewDropProposal(operation: .cancel)
    }

    func tableView(_ tableView: UITableView, performDropWith coordinator: UITableViewDropCoordinator) {
        guard let destinationIndexPath = coordinator.destinationIndexPath else { return }

        for item in coordinator.items {
            if let sourceIndexPath = item.sourceIndexPath {
                tableView.performBatchUpdates({
                    self.tableView(tableView, moveRowAt: sourceIndexPath, to: destinationIndexPath)
                }, completion: nil)
                coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
            } else {
                let itemProvider = item.dragItem.itemProvider
                if itemProvider.hasItemConformingToTypeIdentifier(fdTemplateTypeIdentifier) {
                    itemProvider.loadDataRepresentation(forTypeIdentifier: fdTemplateTypeIdentifier) { data, error in
                        guard let data, error == nil else { return }

                        Task { @MainActor in
                            do {
                                _ = try ChatTemplateManager.shared.importTemplate(from: data)
                            } catch {
                                Logger.app.errorFile("failed to import dropped template: \(error)")
                            }
                        }
                    }
                    coordinator.drop(item.dragItem, toRowAt: destinationIndexPath)
                }
            }
        }
    }
}

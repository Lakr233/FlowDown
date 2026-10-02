//
//  ModelController+Delegates.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import AlertController
import Foundation
import Storage
import UIKit

extension SettingController.SettingContent.ModelController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return
        }
        switch itemIdentifier.type {
        case .local:
            let controller = LocalModelEditorController(identifier: itemIdentifier.identifier)
            navigationController?.pushViewController(controller, animated: true)
        case .cloud:
            let controller = CloudModelEditorController(identifier: itemIdentifier.identifier)
            navigationController?.pushViewController(controller, animated: true)
        }
    }

    func tableView(
        _: UITableView,
        trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        let delete = UIContextualAction(
            style: .destructive,
            title: String(localized: "Delete"),
        ) { _, _, completion in
            switch itemIdentifier.type {
            case .local:
                ModelManager.shared.removeLocalModel(identifier: itemIdentifier.identifier)
            case .cloud:
                ModelManager.shared.removeCloudModel(identifier: itemIdentifier.identifier)
            }
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
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath) else {
            return nil
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            .init(children: self.createModelMenuElements(for: itemIdentifier))
        }
    }
}

extension SettingController.SettingContent.ModelController: UISearchControllerDelegate, UISearchBarDelegate {
    func searchBar(_: UISearchBar, textDidChange _: String) {
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(commitSearch), object: nil)
        perform(#selector(commitSearch), with: nil, afterDelay: 0.25)
    }

    @objc func commitSearch() {
        updateDataSource()
    }
}

extension SettingController.SettingContent.ModelController: UIDocumentPickerDelegate {
    func documentPicker(_: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        let tempDir = disposableResourcesDir
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        for url in urls {
            _ = url.startAccessingSecurityScopedResource()
        }
        ModelManager.shared.importModels(at: urls, controller: self)
    }
}

extension SettingController.SettingContent.ModelController: UITableViewDragDelegate {
    func tableView(_: UITableView, itemsForBeginning _: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        guard let itemIdentifier = dataSource.itemIdentifier(for: indexPath),
              itemIdentifier.type == .cloud,
              let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier)
        else { return [] }

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let plistData = try encoder.encode(model)
            let fileName = "Export-\(model.modelDisplayName.sanitizedFileName)\(model.auxiliaryIdentifier).fdmodel"
            let itemProvider = NSItemProvider(item: plistData as NSSecureCoding, typeIdentifier: "wiki.qaq.fdmodel")
            itemProvider.suggestedName = fileName
            let dragItem = UIDragItem(itemProvider: itemProvider)
            dragItem.localObject = model
            return [dragItem]
        } catch {
            Logger.model.errorFile("failed to encode model: \(error)")
            return []
        }
    }
}

extension SettingController.SettingContent.ModelController {
    func exportModel(_ itemIdentifier: ModelViewModel) {
        guard itemIdentifier.type == .cloud,
              let model = ModelManager.shared.cloudModel(identifier: itemIdentifier.identifier) else { return }

        let tempFileDir = disposableResourcesDir
            .appendingPathComponent(UUID().uuidString)
        let modelName = model.modelDisplayName
        let tempFile = tempFileDir
            .appendingPathComponent("Export-\(modelName.sanitizedFileName)")
            .appendingPathExtension("fdmodel")
        try? FileManager.default.createDirectory(at: tempFileDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: tempFile.path, contents: nil)

        do {
            let encoder = PropertyListEncoder()
            encoder.outputFormat = .xml
            let data = try encoder.encode(model)
            try data.write(to: tempFile, options: .atomic)

            DisposableExporter(deletableItem: tempFile, title: "Export Model").run(anchor: view)
        } catch {
            Logger.model.errorFile("failed to export model: \(error)")
        }
    }
}

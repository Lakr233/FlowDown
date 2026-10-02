//
//  AttachmentsBar.swift
//  RichEditor
//
//  Created by 秋星桥 on 2025/1/16.
//

import AlignedCollectionViewFlowLayout
import AVFoundation
import AVKit
import OrderedCollections
import QuickLook
import UIKit

class AttachmentsBar: EditorSectionView {
    let collectionView: UICollectionView
    let collectionViewLayout = AlignedCollectionViewFlowLayout(
        horizontalAlignment: .justified,
        verticalAlignment: .center,
    )
    var attachmetns: OrderedDictionary<ItemIdentifier, Item> = [:] {
        didSet { updateDataSource() }
    }

    lazy var dataSoruce: DataSource = .init(collectionView: collectionView) { [weak self] _, indexPath, itemIdentifier in
        self?.cellFor(indexPath: indexPath, itemIdentifier: itemIdentifier) ?? .init()
    }

    var inset: UIEdgeInsets = .init(top: 10, left: 10, bottom: 0, right: 10)
    let itemSpacing: CGFloat = 10
    let itemSize = CGSize(width: 80, height: AttachmentsBar.itemHeight)

    static let itemHeight: CGFloat = 80

    weak var delegate: Delegate?
    var isDeletable: Bool = true {
        didSet { collectionView.reloadData() }
    }

    var previewItemDataSource: Any?

    required init() {
        collectionViewLayout.scrollDirection = .horizontal
        collectionViewLayout.minimumInteritemSpacing = itemSpacing
        collectionViewLayout.minimumLineSpacing = itemSpacing
        collectionView = .init(frame: .zero, collectionViewLayout: collectionViewLayout)
        collectionView.backgroundColor = .clear
        collectionView.showsVerticalScrollIndicator = false
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.register(
            AttachmentsImageCell.self,
            forCellWithReuseIdentifier: String(describing: AttachmentsImageCell.self),
        )
        collectionView.register(
            AttachmentsTextCell.self,
            forCellWithReuseIdentifier: String(describing: AttachmentsTextCell.self),
        )
        collectionView.register(
            AttachmentsAudioCell.self,
            forCellWithReuseIdentifier: String(describing: AttachmentsAudioCell.self),
        )
        collectionViewLayout.sectionInset = .init(
            top: 0,
            left: inset.left,
            bottom: 0,
            right: inset.right,
        )
        super.init()
        collectionView.delegate = self
    }

    deinit {
        previewItemDataSource = nil
    }

    override func initializeViews() {
        super.initializeViews()
        clipsToBounds = true
        addSubview(collectionView)
        updateDataSource()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        collectionView.frame = .init(x: 0, y: inset.top, width: bounds.width, height: itemSize.height)
    }

    func idealSize() -> CGSize {
        let itemWidth = attachmetns.values
            .map {
                itemSize(for: $0.type).width
            }
            .reduce(0, +)
        let spacingWidth = CGFloat(attachmetns.count) * itemSpacing
        return .init(
            width: itemWidth + spacingWidth + inset.left + inset.right,
            height: itemSize.height + inset.top + inset.bottom,
        )
    }

    func item(for id: ItemIdentifier) -> Item? {
        attachmetns[id]
    }

    func cellFor(indexPath: IndexPath, itemIdentifier: ItemIdentifier) -> UICollectionViewCell {
        guard let item = item(for: itemIdentifier) else { return .init() }
        switch item.type {
        case .image:
            let cell =
                collectionView.dequeueReusableCell(
                    withReuseIdentifier: String(describing: AttachmentsImageCell.self),
                    for: indexPath,
                ) as! AttachmentsImageCell
            cell.isDeletable = isDeletable
            cell.configure(item: item)
            return cell
        case .text:
            let cell =
                collectionView.dequeueReusableCell(
                    withReuseIdentifier: String(describing: AttachmentsTextCell.self),
                    for: indexPath,
                ) as! AttachmentsTextCell
            cell.isDeletable = isDeletable
            cell.configure(item: item)
            return cell
        case .audio:
            let cell =
                collectionView.dequeueReusableCell(
                    withReuseIdentifier: String(describing: AttachmentsAudioCell.self),
                    for: indexPath,
                ) as! AttachmentsAudioCell
            cell.isDeletable = isDeletable
            cell.configure(item: item)
            return cell
        }
    }

    func updateDataSource() {
        var snapshot = dataSoruce.snapshot()
        if snapshot.sectionIdentifiers.isEmpty {
            snapshot.appendSections([.main])
        }
        let newItems = attachmetns.keys
        for item in snapshot.itemIdentifiers {
            if !newItems.contains(item) {
                snapshot.deleteItems([item])
            }
        }
        for item in newItems {
            if !snapshot.itemIdentifiers.contains(item) {
                snapshot.appendItems([item])
            }
        }
        dataSoruce.apply(snapshot)
        delegate?.attachmentBarDidUpdateAttachments(Array(attachmetns.values))

        if attachmetns.isEmpty {
            doWithAnimation { self.heightPublisher.send(0) }
        } else {
            doWithAnimation { [self] in
                heightPublisher.send(itemSize.height + inset.top + inset.bottom)
            }
        }
    }

    func reloadItem(itemIdentifier: Item.ID) {
        var snapshot = dataSoruce.snapshot()
        snapshot.reloadItems([itemIdentifier])
        dataSoruce.apply(snapshot)
    }

    func delete(itemIdentifier: Item.ID?) {
        guard let itemIdentifier else { return }
        attachmetns.removeValue(forKey: itemIdentifier)
    }

    func insert(item: Item) {
        attachmetns.updateValue(item, forKey: item.id)
        reloadItem(itemIdentifier: item.id)
    }

    func deleteAllItems() {
        attachmetns.removeAll()
    }
}

extension AttachmentsBar: UICollectionViewDelegate, UICollectionViewDelegateFlowLayout {
    var storage: TemporaryStorage? {
        var superview = superview
        while superview != nil {
            if let editor = superview as? RichEditorView {
                return editor.storage
            }
            superview = superview?.superview
        }
        return nil
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: true)
        guard let cell = collectionView.cellForItem(at: indexPath) else { return }
        cell.puddingAnimate()
        guard
            let itemIdentifier = dataSoruce.itemIdentifier(for: indexPath),
            let item = item(for: itemIdentifier)
        else { return }
        presentPreview(for: item)
    }

    func presentPreview(for item: Item) {
        assert(Thread.isMainThread)
        if let storage, item.type == .text {
            let controller = TextEditorController()
            controller.text = item.textRepresentation
            controller.callback = { [weak self] output in
                guard let self else { return }
                var attachment = item
                let url = storage.absoluteURL(attachment.storageSuffix)
                do {
                    try output.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    return
                }
                attachment.textRepresentation = output
                insert(item: attachment)
            }
            parentViewController?.present(controller, animated: true)
            return
        }

        if item.type == .text {
            let controller = TextEditorController()
            controller.text = item.textRepresentation
            controller.rootController.title = String(localized: "Text Viewer")
            #if targetEnvironment(macCatalyst)
                controller.shouldDismissWhenTappedAround = true
                controller.shouldDismissWhenEscapeKeyPressed = true
            #endif
            parentViewController?.present(controller, animated: true)
            return
        }

        if let previewDataSource = makeQuickLookDataSource(for: item, storage: storage) {
            let controller = QLPreviewController()
            controller.dataSource = previewDataSource
            controller.delegate = previewDataSource
            parentViewController?.present(controller, animated: true)
            previewItemDataSource = previewDataSource
            return
        }

        if !item.textRepresentation.isEmpty {
            let controller = TextEditorController()
            controller.text = item.textRepresentation
            controller.rootController.title = String(localized: "Text Viewer")
            #if targetEnvironment(macCatalyst)
                controller.shouldDismissWhenTappedAround = true
                controller.shouldDismissWhenEscapeKeyPressed = true
            #endif
            parentViewController?.present(controller, animated: true)
        }
    }

    private func makeQuickLookDataSource(for item: Item, storage: TemporaryStorage?) -> SingleItemDataSource? {
        let tempDir = disposableResourcesDir
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        func destinationURL(withExtension ext: String) -> URL {
            var url = tempDir.appendingPathComponent(UUID().uuidString)
            if !ext.isEmpty {
                url.appendPathExtension(ext)
            }
            return url
        }

        func cleanup(for url: URL) -> () -> Void {
            { try? FileManager.default.removeItem(at: url) }
        }

        switch item.type {
        case .image:
            if let storage {
                let source = storage.absoluteURL(item.storageSuffix)
                if FileManager.default.fileExists(atPath: source.path) {
                    let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension
                    let destination = destinationURL(withExtension: ext)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: source, to: destination)
                        return SingleItemDataSource(
                            item: destination,
                            name: NSLocalizedString("Image", comment: ""),
                            cleanup: cleanup(for: destination),
                        )
                    } catch {
                        // Fallback to other data sources below.
                    }
                }
            }

            if !item.imageRepresentation.isEmpty {
                let ext = URL(fileURLWithPath: item.storageSuffix).pathExtension
                let resolvedExt = ext.isEmpty ? "png" : ext
                let destination = destinationURL(withExtension: resolvedExt)
                do {
                    try item.imageRepresentation.write(to: destination, options: .atomic)
                    return SingleItemDataSource(
                        item: destination,
                        name: NSLocalizedString("Image", comment: ""),
                        cleanup: cleanup(for: destination),
                    )
                } catch {
                    return nil
                }
            }

            if let image = UIImage(data: item.previewImage), let data = image.pngData() {
                let destination = destinationURL(withExtension: "png")
                do {
                    try data.write(to: destination, options: .atomic)
                    return SingleItemDataSource(
                        item: destination,
                        name: NSLocalizedString("Image", comment: ""),
                        cleanup: cleanup(for: destination),
                    )
                } catch {
                    return nil
                }
            }
            return nil
        case .audio:
            let suffixExtension = URL(fileURLWithPath: item.storageSuffix).pathExtension
            let resolvedExtension = suffixExtension.isEmpty ? "m4a" : suffixExtension

            if let storage {
                let source = storage.absoluteURL(item.storageSuffix)
                if FileManager.default.fileExists(atPath: source.path) {
                    let destination = destinationURL(withExtension: resolvedExtension)
                    do {
                        if FileManager.default.fileExists(atPath: destination.path) {
                            try FileManager.default.removeItem(at: destination)
                        }
                        try FileManager.default.copyItem(at: source, to: destination)
                        return SingleItemDataSource(
                            item: destination,
                            name: item.name,
                            cleanup: cleanup(for: destination),
                        )
                    } catch {
                        // Fallback to raw data below.
                    }
                }
            }

            if !item.imageRepresentation.isEmpty {
                let destination = destinationURL(withExtension: resolvedExtension)
                do {
                    try item.imageRepresentation.write(to: destination, options: .atomic)
                    return SingleItemDataSource(
                        item: destination,
                        name: item.name,
                        cleanup: cleanup(for: destination),
                    )
                } catch {
                    return nil
                }
            }
            return nil
        case .text:
            return nil
        }
    }

    func collectionView(
        _: UICollectionView,
        layout _: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        guard let itemIdentifier = dataSoruce.itemIdentifier(for: indexPath) else { return .zero }
        guard let item = item(for: itemIdentifier) else { return .zero }
        return itemSize(for: item.type)
    }

    private func itemSize(for type: Item.AttachmentType) -> CGSize {
        switch type {
        case .image:
            itemSize
        case .text, .audio:
            .init(width: itemSize.width * 3, height: itemSize.height)
        }
    }
}

//
//  EmojiPicker.swift
//  Kimis
//
//  Created by Lakr Aream on 2022/5/5.
//

import AlignedCollectionViewFlowLayout
import Combine
import UIKit

class EmojiPickerView: UIView, UISearchBarDelegate {
    let collectionView: UICollectionView
    static let lineSpacing: CGFloat = 4
    static let itemSpacing: CGFloat = 4

    let provider = EmojiProvider()

    let contentView = UIView()
    var rawDataSource = [EmojiSection]()
    @Published var searchText: String = ""
    let searchBar = UISearchBar()
    var dataSource: [EmojiSection] = []

    var selectingEmoji: ((EmojiProvider.Emoji) -> Void)?

    var cancellable = Set<AnyCancellable>()

    init() {
        let alignedFlowLayout = AlignedCollectionViewFlowLayout(
            horizontalAlignment: .justified,
            verticalAlignment: .center,
        )
        alignedFlowLayout.scrollDirection = .vertical
        alignedFlowLayout.sectionInset = UIEdgeInsets()
        alignedFlowLayout.minimumInteritemSpacing = Self.itemSpacing
        alignedFlowLayout.minimumLineSpacing = Self.lineSpacing
        alignedFlowLayout.sectionHeadersPinToVisibleBounds = true
        collectionView = UICollectionView(
            frame: CGRect(),
            collectionViewLayout: alignedFlowLayout,
        )
        collectionView.register(
            EmojiPickerCell.self,
            forCellWithReuseIdentifier: EmojiPickerCell.cellId,
        )
        collectionView.register(
            EmojiPickerSectionHeader.self,
            forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
            withReuseIdentifier: EmojiPickerSectionHeader.headerId,
        )
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 8, bottom: 8, right: 8)
        collectionView.backgroundView = UIView()
        collectionView.backgroundColor = .clear

        super.init(frame: CGRect())

        // avoid stuff being draw at that triangle
        contentView.clipsToBounds = true
        collectionView.clipsToBounds = true

        addSubview(contentView)

        searchBar.backgroundColor = .clear
        searchBar.backgroundImage = UIImage()
        searchBar.placeholder = String(localized: "Search Emoji")
        searchBar.searchTextField.autocorrectionType = .no
        searchBar.searchTextField.autocapitalizationType = .none
        searchBar.delegate = self
        contentView.addSubview(searchBar)

        collectionView.dataSource = self
        collectionView.delegate = self

        contentView.addSubview(collectionView)

        let queue = DispatchQueue(label: "search")
        $searchText
            .throttle(for: .seconds(0.5), scheduler: queue, latest: true)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] v in
                self?.buildSearchResultAndReload(for: v)
            }
            .store(in: &cancellable)

        prepareDataSource()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = bounds
        contentView.frame = bounds
        let searchBarHeight = searchBar.intrinsicContentSize.height
        searchBar.frame = CGRect(x: 0, y: 0, width: bounds.width, height: searchBarHeight)
        collectionView.frame = CGRect(
            x: 0,
            y: searchBar.frame.maxY,
            width: bounds.width,
            height: bounds.height - searchBarHeight
        )
    }

    func searchBar(_: UISearchBar, textDidChange searchText: String) {
        self.searchText = searchText
    }
}

class EmojiPickerViewController: UIViewController, UIPopoverPresentationControllerDelegate {
    let pickerView = EmojiPickerView()

    init(sourceView: UIView, selectingEmoji: @escaping (EmojiProvider.Emoji) -> Void) {
        super.init(nibName: nil, bundle: nil)

        let bg = UIView().with { $0.backgroundColor = .background }
        view.addSubview(bg)
        bg.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(-128)
        }

        pickerView.selectingEmoji = { emoji in
            selectingEmoji(emoji)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self.dismiss(animated: true, completion: nil)
        }

        modalPresentationStyle = .popover
        preferredContentSize = CGSize(width: 400, height: 300)
        popoverPresentationController?.delegate = self
        popoverPresentationController?.sourceView = sourceView
        let padding: CGFloat = 4
        popoverPresentationController?.sourceRect = .init(
            x: -padding,
            y: -padding,
            width: sourceView.frame.width + padding * 2,
            height: sourceView.frame.height + padding * 2,
        )
        popoverPresentationController?.permittedArrowDirections = .any
        view.addSubview(pickerView)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    func adaptivePresentationStyle(
        for _: UIPresentationController,
        traitCollection _: UITraitCollection,
    ) -> UIModalPresentationStyle {
        .none
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()

        let bounds = view.bounds
        pickerView.frame = bounds.inset(by: view.safeAreaInsets)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        // release any circle ref from caller
        pickerView.selectingEmoji = { _ in }
    }
}

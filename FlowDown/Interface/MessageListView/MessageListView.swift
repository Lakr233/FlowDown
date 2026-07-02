//
//  Created by ktiays on 2025/1/22.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import AlertController
import Combine
import ListViewKit
import Litext
import MarkdownView
import SnapKit
import Storage
import UIKit

final class MessageListView: UIView {
    private lazy var listView: ListViewKit.ListView = .init()

    var contentSize: CGSize {
        listView.contentSize
    }

    lazy var dataSource: ListViewDiffableDataSource<Entry> = .init(listView: listView)

    private var entryCount = 0
    private let updateQueue = DispatchQueue(label: "MessageListView.UpdateQueue", qos: .userInteractive)

    private var isFirstLoad: Bool = true
    private let autoScrollTolerance: CGFloat = 2

    var session: ConversationSession! {
        didSet {
            isFirstLoad = true
            alpha = 0
            sessionScopedCancellables.forEach { $0.cancel() }
            sessionScopedCancellables.removeAll()
            Publishers.CombineLatest(
                session.messagesDidChange,
                loadingIndicatorPublisher,
            )
            .receive(on: updateQueue)
            .sink { [weak self] v1, v2 in
                guard let self else { return }
                updateFromUpstreamPublisher(v1.0, v1.1, isLoading: v2)
            }
            .store(in: &sessionScopedCancellables)
            session.userDidSendMessage.sink { [unowned self] _ in
                isAutoScrollingToBottom = true
            }
            .store(in: &sessionScopedCancellables)
        }
    }

    /// A Boolean value that indicates whether the list should automatically scroll to the bottom
    /// when the messages change.
    ///
    /// When `true`, the list will scroll to the bottom to make the latest message visible.
    private var isAutoScrollingToBottom: Bool = true
    private var viewCancellables: Set<AnyCancellable> = .init()
    private var sessionScopedCancellables: Set<AnyCancellable> = .init()
    private let loadingIndicatorPublisher = CurrentValueSubject<String?, Never>(nil)

    var contentSafeAreaInsets: UIEdgeInsets = .zero {
        didSet {
            setNeedsLayout()
        }
    }

    var scrollIndicatorInsets: UIEdgeInsets = .zero {
        didSet {
            setNeedsLayout()
        }
    }

    static let listRowInsets: UIEdgeInsets = .init(top: 0, left: 20, bottom: 16, right: 20)
    var theme: MarkdownTheme = .default {
        didSet {
            listView.reloadData()
        }
    }

    private(set) lazy var labelForSizeCalculation: TextLabelView = .init()
    private(set) lazy var markdownViewForSizeCalculation: MarkdownTextView = .init()
    private(set) lazy var markdownPackageCache: MarkdownPackageCache = .init()

    init() {
        super.init(frame: .zero)

        listView.delegate = self
        listView.adapter = self
        listView.alwaysBounceVertical = true
        listView.alwaysBounceHorizontal = false
        listView.contentInsetAdjustmentBehavior = .never
        listView.automaticallyAdjustsScrollIndicatorInsets = false
        listView.showsHorizontalScrollIndicator = false
        addSubview(listView)
        listView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        listView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }

        MarkdownTheme.fontScaleDidChange
            .ensureMainThread()
            .sink { [weak self] _ in
                guard let self else { return }
                theme = MarkdownTheme.default
                listView.reloadData()
                updateList()
            }
            .store(in: &viewCancellables)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        let wasNearBottom = isContentOffsetNearBottom()
        super.layoutSubviews()

        listView.contentInset = contentSafeAreaInsets
        listView.scrollIndicatorInsets = scrollIndicatorInsets

        if isAutoScrollingToBottom || wasNearBottom {
            let targetOffset = listView.maximumContentOffset
            if abs(listView.contentOffset.y - targetOffset.y) > autoScrollTolerance {
                listView.scroll(to: targetOffset)
            }
            if wasNearBottom {
                isAutoScrollingToBottom = true
            }
        }
    }

    private func updateAutoScrolling() {
        if isContentOffsetNearBottom() {
            isAutoScrollingToBottom = true
        }
    }

    private func isContentOffsetNearBottom(tolerance: CGFloat? = nil) -> Bool {
        let tolerance = tolerance ?? autoScrollTolerance
        return abs(listView.contentOffset.y - listView.maximumContentOffset.y) <= tolerance
    }

    func loading(with message: String = .init()) {
        loadingIndicatorPublisher.send(message)
    }

    func stopLoading() {
        loadingIndicatorPublisher.send(nil)
    }

    func handleLinkTapped(_ link: LinkPayload, in _: NSRange, at point: CGPoint) {
        // long press handled
        guard parentViewController?.presentedViewController == nil else { return }
        switch link {
        case let .url(url):
            processLinkTapped(link: url, rawValue: url.absoluteString, location: point)
        case let .string(string):
            let charset: CharacterSet = [
                .init(charactersIn: #""'“”"#),
                .whitespacesAndNewlines,
            ].reduce(into: .init()) { $0.formUnion($1) }
            var candidate = string.trimmingCharacters(in: charset)
            if var comp = URLComponents(string: candidate) {
                comp.path = comp.path.urlEncoded
                if let url = comp.url {
                    candidate = url.absoluteString
                }
            }
            processLinkTapped(link: .init(string: candidate), rawValue: string, location: point)
        }
    }

    private func processLinkTapped(link: URL?, rawValue: String, location _: CGPoint) {
        guard let link,
              let scheme = link.scheme,
              ["http", "https"].contains(scheme)
        else {
            let alert = AlertViewController(
                title: "Unable to open link.",
                message: "We are unable to process the link you tapped, either it is invalid or not supported.",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "Dismiss") {
                    context.dispose()
                }
                context.addAction(title: "Copy Content", attribute: .accent) {
                    UIPasteboard.general.string = rawValue
                    context.dispose()
                }
            }
            parentViewController?.present(alert, animated: true)
            return
        }

        let alert = AlertViewController(
            title: "Open Link",
            message: "Do you want to open this link in your default browser?\n\n\(link.absoluteString)",
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Open", attribute: .accent) {
                context.dispose {
                    UIApplication.shared.open(link)
                }
            }
        }
        parentViewController?.present(alert, animated: true)
    }

    func updateList() {
        let entries = entries(from: session.messages)
        dataSource.applySnapshot(using: entries, animatingDifferences: false)
    }

    func updateFromUpstreamPublisher(_ messages: [Message], _ scrolling: Bool, isLoading: String?) {
        assert(!Thread.isMainThread)
        var entries = entries(from: messages)

        for entry in entries {
            switch entry {
            case let .aiContent(_, messageRepresentation):
                _ = markdownPackageCache.package(for: messageRepresentation, theme: theme)
            default: break
            }
        }

        if let isLoading { entries.append(.activityReporting(isLoading)) }

        let shouldScrolling = scrolling && isAutoScrollingToBottom

        entryCount = entries.count
        Task { @MainActor [weak self] in
            guard let self else { return }
            if isFirstLoad || alpha == 0 {
                isFirstLoad = false
                dataSource.applySnapshot(using: entries, animatingDifferences: false)
                listView.setContentOffset(.init(x: 0, y: listView.maximumContentOffset.y), animated: false)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.1))
                    await MainActor.run {
                        guard let self else { return }
                        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
                    }
                }
            } else {
                dataSource.applySnapshot(using: entries, animatingDifferences: true)
                if shouldScrolling {
                    listView.scroll(to: listView.maximumContentOffset)
                }
            }
        }
    }
}

extension MessageListView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_: UIScrollView) {
        isAutoScrollingToBottom = false
    }

    func scrollViewDidEndDecelerating(_: UIScrollView) {
        updateAutoScrolling()
    }

    func scrollViewDidEndDragging(_: UIScrollView, willDecelerate decelerate: Bool) {
        if !decelerate {
            updateAutoScrolling()
        }
    }
}

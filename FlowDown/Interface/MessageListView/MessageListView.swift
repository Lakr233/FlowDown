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
    let listView = RetainingListView()

    var contentSize: CGSize {
        listView.contentSize
    }

    /// The entries currently displayed by the list.
    var entries: [Entry] {
        listView.content
    }

    private let updateQueue = DispatchQueue(label: "MessageListView.UpdateQueue", qos: .userInteractive)

    private var isFirstLoad: Bool = true
    private let autoScrollTolerance: CGFloat = 2

    var session: ConversationSession! {
        didSet {
            isFirstLoad = true
            alpha = 0
            sessionScopedCancellables.forEach { $0.cancel() }
            sessionScopedCancellables.removeAll()
            // Ahead of the new session's first update on the queue: nothing
            // held back from the last one is built again.
            updateQueue.async { [weak self] in
                guard let self else { return }
                pendingThoughtFlush?.cancel()
                pendingThoughtFlush = nil
                lastUpstreamState = nil
                thoughtThrottle = .init()
            }
            let sessionID = session.id
            Publishers.CombineLatest4(
                session.messagesDidChange,
                session.activityText.removeDuplicates(),
                ConversationSessionManager.shared.executingSessionsPublisher
                    .map { $0.contains(sessionID) }
                    .removeDuplicates(),
                // Turning it on or off rebuilds the rows on screen.
                InlineActivityStepsSetting.publisher,
            )
            .receive(on: updateQueue)
            .sink { [weak self] v1, v2, isExecuting, showsSteps in
                guard let self else { return }
                updateFromUpstreamPublisher(
                    v1.0,
                    v1.1,
                    isLoading: v2,
                    isExecuting: isExecuting,
                    showsSteps: showsSteps,
                )
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

    /// The least space beside a row's content.
    static let rowHorizontalPadding: CGFloat = 20
    /// The widest a row's content gets: the editor's card at its widest
    /// (750 pt less its 10 pt gap each side), so text lines up with it.
    static let rowReadableWidth: CGFloat = 730
    /// Between one row's content and the next.
    static let rowSpacing: CGFloat = 16

    /// A row's insets at `width`: the padding, or more to centre the content
    /// in the readable width, and the spacing below it.
    static func listRowInsets(for width: CGFloat) -> UIEdgeInsets {
        let side = max(rowHorizontalPadding, ((width - rowReadableWidth) / 2).rounded(.down))
        return .init(top: 0, left: side, bottom: rowSpacing, right: side)
    }

    /// The reply's theme: the reader's font size with the chat's spacing and
    /// colours (`ChatMarkdownView.chatTheme(from:)`).
    var theme: MarkdownTheme = ChatMarkdownView.chatTheme(from: .default) {
        didSet {
            guard oldValue != theme else { return }
            // Every pooled sizing view was built for the old theme and would
            // otherwise sit there until eviction pushed it out.
            markdownSizingViewPool.removeAll()
            listView.reloadData()
        }
    }

    /// The trace sheet open from a summary in this list, which follows it.
    weak var openTrace: TraceController?
    private(set) lazy var markdownSizingViewPool: MarkdownSizingViewPool = .init()
    private(set) lazy var markdownPackageCache: MarkdownPackageCache = .init()
    /// Every call's reason, for summaries that list their steps.
    let toolReasons = ToolReasonCache()

    /// What the update queue last built the list from, to build it again
    /// once a thought's held-back text may show (`InlineThoughtThrottle`).
    private struct UpstreamState {
        let messages: [Message]
        let scrolling: Bool
        let isLoading: String?
        let isExecuting: Bool
        let showsSteps: Bool
    }

    /// Confined to the update queue, like everything below it.
    private var thoughtThrottle = InlineThoughtThrottle()
    private var lastUpstreamState: UpstreamState?
    private var pendingThoughtFlush: DispatchWorkItem?

    #if DEBUG
        // TEMP scroll-diag: remove after #2.
        private var scrollDiagObservation: NSKeyValueObservation?
        private var scrollDiagWriteCount = 0
        private var scrollDiagMaxStep: CGFloat = 0
        private var scrollDiagLastFlush: CFTimeInterval = CACurrentMediaTime()
        private func installScrollDiagHeartbeat() {
            scrollDiagObservation = listView.observe(\.contentOffset, options: [.old, .new]) { [weak self] view, change in
                guard let self, let old = change.oldValue, let new = change.newValue else { return }
                let dy = abs(new.y - old.y)
                guard dy > 0.1 else { return }
                scrollDiagWriteCount += 1
                scrollDiagMaxStep = max(scrollDiagMaxStep, dy)
                let now = CACurrentMediaTime()
                if now - scrollDiagLastFlush > 0.5 {
                    Logger.ui.infoFile("[scroll-diag] heartbeat writes=\(scrollDiagWriteCount) maxStep=\(Int(scrollDiagMaxStep)) offset=\(Int(new.y)) max=\(Int(view.maximumContentOffset.y))")
                    scrollDiagWriteCount = 0
                    scrollDiagMaxStep = 0
                    scrollDiagLastFlush = now
                }
            }
        }
    #endif

    init() {
        super.init(frame: .zero)

        listView.delegate = self
        registerRows()
        // Only AI rows are worth laying out ahead of a scroll: typesetting a
        // Markdown document at a new width is what stalls one.
        listView.preparedRowHeight = { [weak self] entry, listWidth in
            guard let self, case let .aiContent(_, message) = entry else { return nil }
            return aiRowHeight(for: message, inListWidth: listWidth)
        }
        listView.alwaysBounceVertical = true
        listView.alwaysBounceHorizontal = false
        listView.contentInsetAdjustmentBehavior = .never
        listView.automaticallyAdjustsScrollIndicatorInsets = false
        listView.showsHorizontalScrollIndicator = false
        // Rows trail the scroll on springs; the content offset itself is
        // untouched, so the auto-scroll-to-bottom math is unaffected.
        // Same tuning as AirBuild, by feel.
        listView.rowAnimator = ListBouncyAnimator(damping: 0.975, frequency: 25.0)
        addSubview(listView)
        listView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        listView.gestureRecognizers?.forEach {
            guard $0 is UIPanGestureRecognizer else { return }
            $0.cancelsTouchesInView = false
        }

        #if DEBUG
            installScrollDiagHeartbeat()
        #endif

        MarkdownTheme.fontScaleDidChange
            .ensureMainThread()
            .sink { [weak self] _ in
                guard let self else { return }
                theme = ChatMarkdownView.chatTheme(from: .default)
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
                #if DEBUG
                    // TEMP scroll-diag: remove after #2.
                    Logger.ui.infoFile("[scroll-diag] layout scroll offset=\(Int(listView.contentOffset.y)) target=\(Int(targetOffset.y))")
                #endif
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

        // The alert initializer resolves to its plain-String overload, which uses
        // the finished string as the lookup key — an interpolated message never
        // matches the catalog, so it must be localized here first.
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

    func updateList(animated: Bool = false) {
        let isExecuting = ConversationSessionManager.shared.isSessionExecuting(session.id)
        let entries = entries(
            from: session.messages,
            isExecuting: isExecuting,
            showsSteps: InlineActivityStepsSetting.isEnabled(),
        )
        listView.apply(entries, animated: animated)
    }

    func updateFromUpstreamPublisher(
        _ messages: [Message],
        _ scrolling: Bool,
        isLoading: String?,
        isExecuting: Bool,
        showsSteps: Bool = false,
    ) {
        assert(!Thread.isMainThread)
        #if DEBUG
            // TEMP scroll-diag: remove after #2.
            Logger.ui.infoFile("[scroll-diag] upstream scrolling=\(scrolling) auto=\(isAutoScrollingToBottom) loading=\(isLoading ?? "nil")")
        #endif
        var entries = entries(from: messages, isExecuting: isExecuting, showsSteps: showsSteps)
        if showsSteps {
            lastUpstreamState = .init(
                messages: messages,
                scrolling: scrolling,
                isLoading: isLoading,
                isExecuting: isExecuting,
                showsSteps: showsSteps,
            )
            if let wait = thoughtThrottle.apply(to: &entries, now: CACurrentMediaTime()) {
                scheduleThoughtFlush(after: wait)
            }
        } else {
            lastUpstreamState = nil
        }

        for entry in entries {
            switch entry {
            case let .aiContent(_, messageRepresentation):
                _ = markdownPackageCache.package(for: messageRepresentation, theme: theme)
            default: break
            }
        }

        // A running summary already says the turn is at work; the status line
        // stands in only where there is none.
        let endsInRunningSummary = if case let .activity(summary)? = entries.last { summary.isRunning } else { false }
        if let isLoading, !endsInRunningSummary { entries.append(.activityReporting(isLoading)) }

        let shouldScrolling = scrolling && isAutoScrollingToBottom

        Task { @MainActor [weak self] in
            guard let self else { return }
            if isFirstLoad || alpha == 0 {
                isFirstLoad = false
                listView.apply(entries)
                listView.setContentOffset(.init(x: 0, y: listView.maximumContentOffset.y), animated: false)
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(0.1))
                    await MainActor.run {
                        guard let self else { return }
                        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
                    }
                }
            } else {
                listView.apply(entries, animated: true)
                updateOpenTrace()
                #if DEBUG
                    // TEMP scroll-diag: remove after #2.
                    Logger.ui.infoFile("[scroll-diag] apply shouldScroll=\(shouldScrolling) offset=\(Int(listView.contentOffset.y)) max=\(Int(listView.maximumContentOffset.y))")
                #endif
                if shouldScrolling {
                    listView.scroll(to: listView.maximumContentOffset)
                }
            }
        }
    }

    /// Builds the list again once a held-back thought may show, so its last
    /// text appears even when nothing else arrives after it.
    private func scheduleThoughtFlush(after wait: TimeInterval) {
        guard pendingThoughtFlush == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingThoughtFlush = nil
            guard let state = lastUpstreamState, state.showsSteps else { return }
            updateFromUpstreamPublisher(
                state.messages,
                state.scrolling,
                isLoading: state.isLoading,
                isExecuting: state.isExecuting,
                showsSteps: state.showsSteps,
            )
        }
        pendingThoughtFlush = item
        updateQueue.asyncAfter(deadline: .now() + wait, execute: item)
    }
}

extension MessageListView: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_: UIScrollView) {
        #if DEBUG
            // TEMP scroll-diag: remove after #2.
            Logger.ui.infoFile("[scroll-diag] willBeginDragging -> auto=false")
        #endif
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

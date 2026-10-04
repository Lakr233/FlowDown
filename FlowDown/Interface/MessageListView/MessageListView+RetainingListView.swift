//
//  MessageListView+RetainingListView.swift
//  FlowDown
//

import ListViewKit
import QuartzCore
import UIKit

extension MessageListView {
    /// The message list, giving every entry a row view of its own.
    ///
    /// Rows are never handed from one entry to another. A row the viewport
    /// leaves is only taken out of the view hierarchy, so the render server
    /// stops drawing it, and comes back as the same view when its entry is
    /// mounted again. Filling a reused row means rebuilding a whole Markdown
    /// document; bringing back the one that already shows it costs nothing,
    /// and the reply being written keeps the text in flight and the pacing of
    /// its stream when it is scrolled away and back.
    ///
    /// Views live as long as their entries, so a long conversation holds one
    /// view per entry. A row is let go when its entry leaves the list, or
    /// when the entry turns into another row type.
    ///
    /// When the list changes width, the rows it keeps off screen are laid out
    /// again at the new width ahead of time, a slice at a time between frames,
    /// so scrolling back to them mounts rows that are already typeset.
    final class RetainingListView: ListView<Entry> {
        /// The height of an off-screen row at a list width, for the rows worth
        /// laying out ahead of time; nil leaves the row until it is mounted.
        /// It must agree with the row's registered height, or the row is laid
        /// out again when it is mounted.
        var preparedRowHeight: ((Entry, CGFloat) -> CGFloat?)?

        /// Main-thread time one preparation pass may spend. At 120Hz a frame
        /// is 8.3ms; this leaves the rest of it to rendering.
        static let preparationBudget: CFTimeInterval = 0.004

        /// How long the width must hold still before preparation starts. A
        /// window being resized changes it every frame, and anything laid out
        /// mid-resize is laid out at a width about to be replaced.
        static let widthSettleDelay: TimeInterval = 0.15

        private var retainedRows: [Entry.ID: (view: ListRowView, registration: Int)] = [:]
        private var recyclingEntryID: Entry.ID?
        private var mountingEntryID: Entry.ID?

        private var preparationWidth: CGFloat = 0
        /// Rows `preparedRowHeight` declined at `preparationWidth`.
        private var rowsSkippedByPreparation: Set<Entry.ID> = []
        private var preparationTimer: Timer?
        private var isPreparationScheduled = false

        override func recycleRow(with identifier: Entry.ID) -> ListRowView? {
            recyclingEntryID = identifier
            defer { recyclingEntryID = nil }
            return super.recycleRow(with: identifier)
        }

        override func enqueueReusableRowView(_ view: ListRowView, forRegistrationAt registrationIndex: Int) {
            guard let recyclingEntryID else {
                super.enqueueReusableRowView(view, forRegistrationAt: registrationIndex)
                return
            }
            retainedRows[recyclingEntryID] = (view, registrationIndex)
        }

        override func mountRowView(at index: Int) {
            mountingEntryID = content[index].id
            defer { mountingEntryID = nil }
            super.mountRowView(at: index)
        }

        /// Hands back the entry's own row, or nil so the list makes a new one.
        override func dequeueReusableRowView(forRegistrationAt registrationIndex: Int) -> ListRowView? {
            guard let mountingEntryID,
                  let row = retainedRows.removeValue(forKey: mountingEntryID),
                  row.registration == registrationIndex
            else { return nil }
            return row.view
        }

        override func apply(_ newItems: [Entry], animated: Bool = false) {
            super.apply(newItems, animated: animated)
            let identifiers = Set(newItems.map(\.id))
            retainedRows = retainedRows.filter { identifiers.contains($0.key) }
        }

        override func reloadData() {
            retainedRows.removeAll()
            super.reloadData()
        }

        // MARK: - Preparing off-screen rows

        override func layoutContent() {
            super.layoutContent()
            let width = bounds.width
            guard width > 0, width != preparationWidth else { return }
            preparationWidth = width
            rowsSkippedByPreparation.removeAll()
            // Restarted on every change, so it fires once the width settles.
            preparationTimer?.invalidate()
            let timer = Timer(timeInterval: Self.widthSettleDelay, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.preparationTimer = nil
                    self?.schedulePreparation()
                }
            }
            RunLoop.main.add(timer, forMode: .default)
            preparationTimer = timer
        }

        /// Queues one preparation pass.
        ///
        /// Default mode only: a drag and its deceleration run the run loop in
        /// tracking mode, so preparation waits for the scroll to end instead of
        /// competing with it for the frame.
        private func schedulePreparation() {
            guard !isPreparationScheduled else { return }
            isPreparationScheduled = true
            RunLoop.main.perform(inModes: [.default]) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isPreparationScheduled = false
                    if self.prepareRetainedRows(budget: Self.preparationBudget) {
                        self.schedulePreparation()
                    }
                }
            }
        }

        /// Lays out off-screen rows at the current width, nearest to the
        /// viewport first, until `budget` is spent. Returns whether any row is
        /// left to lay out.
        @discardableResult
        func prepareRetainedRows(budget: CFTimeInterval) -> Bool {
            guard let preparedRowHeight, preparationWidth > 0 else { return false }
            let width = preparationWidth
            let stale = retainedRows.filter { identifier, row in
                row.view.bounds.width != width && !rowsSkippedByPreparation.contains(identifier)
            }
            guard !stale.isEmpty else { return false }

            let viewportMidY = contentOffset.y + bounds.height / 2
            var pending: [(distance: CGFloat, index: Int, view: ListRowView)] = []
            for (index, item) in content.enumerated() {
                guard let row = stale[item.id] else { continue }
                pending.append((abs(rectForRow(at: index).midY - viewportMidY), index, row.view))
            }
            pending.sort { $0.distance < $1.distance }

            let deadline = CACurrentMediaTime() + budget
            for (offset, row) in pending.enumerated() {
                if offset > 0, CACurrentMediaTime() >= deadline { return true }
                let item = content[row.index]
                guard let height = preparedRowHeight(item, width) else {
                    rowsSkippedByPreparation.insert(item.id)
                    continue
                }
                row.view.frame.size = CGSize(width: width, height: height)
                row.view.layoutIfNeeded()
            }
            return false
        }
    }
}

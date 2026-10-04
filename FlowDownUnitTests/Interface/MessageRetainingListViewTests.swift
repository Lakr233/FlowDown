@preconcurrency @testable import FlowDown
import ListViewKit
import Testing
import UIKit

@Suite(.serialized)
struct MessageRetainingListViewTests {
    private final class Row: ListRowView {}

    @MainActor
    private func makeList(rowCount: Int) -> (MessageListView.RetainingListView, [MessageListView.Entry]) {
        let list = MessageListView.RetainingListView(frame: .init(x: 0, y: 0, width: 320, height: 200))
        list.rows {
            ListRow(Row.self).height { _, _ in 100 }
        }
        let entries = (0 ..< rowCount).map { MessageListView.Entry.hint("\($0)", "\($0)") }
        list.apply(entries)
        list.layoutIfNeeded()
        return (list, entries)
    }

    @MainActor
    private func scroll(_ list: MessageListView.RetainingListView, toY y: CGFloat) {
        list.contentOffset = .init(x: 0, y: y)
        list.setNeedsLayout()
        list.layoutIfNeeded()
    }

    @Test
    @MainActor
    func row_scrolledAwayAndBack_isTheSameViewAndOffScreenMeanwhile() throws {
        let (list, entries) = makeList(rowCount: 20)
        let identifier = entries[0].id
        let row = try #require(list.rowView(for: identifier))

        scroll(list, toY: list.maximumContentOffset.y)
        #expect(list.rowView(for: identifier) == nil)
        #expect(row.superview == nil)
        #expect(!list.visibleRowViews.contains { $0 === row })

        scroll(list, toY: 0)
        #expect(list.rowView(for: identifier) === row)
    }

    @Test
    @MainActor
    func rows_areNeverHandedToAnotherEntry() throws {
        let (list, entries) = makeList(rowCount: 20)
        let topRows = list.visibleRowViews.map(ObjectIdentifier.init)

        scroll(list, toY: list.maximumContentOffset.y)
        let bottomRows = list.visibleRowViews.map(ObjectIdentifier.init)

        #expect(!entries.isEmpty)
        #expect(Set(topRows).isDisjoint(with: bottomRows))
    }

    @Test
    @MainActor
    func removedEntry_letsItsRowGo() throws {
        let (list, entries) = makeList(rowCount: 20)
        let identifier = entries[0].id
        weak var row = list.rowView(for: identifier)
        #expect(row != nil)

        scroll(list, toY: list.maximumContentOffset.y)
        list.apply(Array(entries.dropFirst()))
        list.apply(entries)
        scroll(list, toY: 0)

        #expect(list.rowView(for: identifier) !== row)
    }

    @Test
    @MainActor
    func widthChange_laysOutOffScreenRowsAtTheNewWidth() throws {
        let (list, entries) = makeList(rowCount: 20)
        list.preparedRowHeight = { entry, _ in entry.id == entries[1].id ? nil : 100 }
        let prepared = try #require(list.rowView(for: entries[0].id))
        let declined = try #require(list.rowView(for: entries[1].id))
        scroll(list, toY: list.maximumContentOffset.y)

        list.frame.size.width = 280
        list.layoutIfNeeded()
        #expect(prepared.bounds.width == 320)

        #expect(!list.prepareRetainedRows(budget: .infinity))
        #expect(prepared.bounds.size == CGSize(width: 280, height: 100))
        #expect(declined.bounds.width == 320)
    }
}

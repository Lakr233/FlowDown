@preconcurrency @testable import FlowDown
import Foundation
import ListViewKit
import MarkdownView
import Storage
import Testing
import UIKit

/// A reply is measured on its own row where it has one: filling a view in is
/// most of what a reply costs to show, and a sizing view is filled in only
/// to be thrown away.
@Suite(.serialized)
struct MessageListOwnRowHeightTests {
    private let markdown = """
    Some **bold** text and a [link](https://example.com) that has to wrap when
    the container gets narrow enough to break the line.

    - first item
    - second item

    ```swift
    let value = 42
    ```

    | Name | Cost |
    | --- | --- |
    | one | 3 ms |

    A closing paragraph so the document has more than one block to stack.
    """

    @MainActor
    private func withList(
        _ body: @MainActor (MessageListView, MessageListView.MessageRepresentation) throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Own Row \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let message = session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: self.markdown)
        }
        let list = MessageListView()
        list.frame = CGRect(x: 0, y: 0, width: 600, height: 400)
        list.layoutIfNeeded()
        try body(list, .init(from: message))
    }

    /// What a pooled sizing view answers, on a list that has no row for it.
    @MainActor
    private func pooledHeight(
        _ list: MessageListView,
        _ message: MessageListView.MessageRepresentation,
        width: CGFloat,
    ) -> CGFloat {
        list.aiRowHeight(for: message, of: .aiContent("unlisted", message), inListWidth: width, buildsRow: false)
    }

    @Test
    @MainActor
    func `a reply about to mount is built once and mounted as the row it was measured on`() async throws {
        try await withList { list, message in
            let entry = MessageListView.Entry.aiContent(message.id, message)
            #expect(list.listView.row(for: entry.id) == nil)

            let height = list.aiRowHeight(for: message, of: entry, inListWidth: 600, buildsRow: true)
            let built = try #require(list.listView.row(for: entry.id) as? AiMessageView)
            #expect(built.superview == nil)
            #expect(abs(height - pooledHeight(list, message, width: 600)) < 0.5)

            list.listView.apply([entry])
            list.listView.layoutIfNeeded()
            #expect(list.listView.rowView(for: entry.id) === built)
            #expect(abs(built.bounds.height - height) < 0.5)
        }
    }

    @Test
    @MainActor
    func `a reply measured ahead of any need builds no row`() async throws {
        try await withList { list, message in
            let entry = MessageListView.Entry.aiContent(message.id, message)
            _ = list.aiRowHeight(for: message, of: entry, inListWidth: 600, buildsRow: false)
            #expect(list.listView.row(for: entry.id) == nil)
        }
    }

    @Test
    @MainActor
    func `the list builds the row while it measures the replies it is about to show`() async throws {
        try await withList { list, message in
            let entry = MessageListView.Entry.aiContent(message.id, message)
            list.listView.apply([entry])
            list.listView.layoutIfNeeded()
            let row = try #require(list.listView.rowView(for: entry.id) as? AiMessageView)
            #expect(abs(row.bounds.height - pooledHeight(list, message, width: 600)) < 0.5)
        }
    }

    @Test
    @MainActor
    func `a mounted row answers at every width as a sizing view would`() async throws {
        try await withList { list, message in
            let entry = MessageListView.Entry.aiContent(message.id, message)
            list.listView.apply([entry])
            list.listView.layoutIfNeeded()
            for width in stride(from: CGFloat(320), through: 900, by: 58) {
                let own = list.aiRowHeight(for: message, of: entry, inListWidth: width, buildsRow: false)
                let pooled = pooledHeight(list, message, width: width)
                #expect(abs(own - pooled) < 0.5, "width \(width): \(own) vs \(pooled)")
            }
        }
    }

    @Test
    @MainActor
    func `a reply still being written is never measured on its row`() async throws {
        try await withList { list, message in
            var streaming = message
            streaming.isStreaming = true
            let entry = MessageListView.Entry.aiContent(streaming.id, streaming)
            let height = list.aiRowHeight(for: streaming, of: entry, inListWidth: 600, buildsRow: true)
            #expect(list.listView.row(for: entry.id) == nil)
            #expect(height > 0)
        }
    }

    @Test
    @MainActor
    func `a row whose update has yet to reach its view does not answer for it`() async throws {
        try await withList { list, message in
            let entry = MessageListView.Entry.aiContent(message.id, message)
            list.listView.apply([entry])
            list.listView.layoutIfNeeded()
            let row = try #require(list.listView.rowView(for: entry.id) as? AiMessageView)

            var longer = message
            longer.content = markdown + "\n\nAnd a paragraph the row has not been handed yet."
            let changed = MessageListView.Entry.aiContent(longer.id, longer)
            // The height is asked for before the row is filled in again.
            let height = list.aiRowHeight(for: longer, of: changed, inListWidth: 600, buildsRow: true)
            #expect(abs(height - pooledHeight(list, longer, width: 600)) < 0.5)
            #expect(height > row.bounds.height)

            // And after: the update goes through the stream view, which shows
            // it a moment later, so the row still does not answer.
            let package = list.markdownPackageCache.package(for: longer, theme: list.theme)
            row.setMarkdownPackage(package, for: longer.id, isStreaming: false)
            #expect(row.contentHeight(showing: package, width: 500) == nil)
        }
    }
}

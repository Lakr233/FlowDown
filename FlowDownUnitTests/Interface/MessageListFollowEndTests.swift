@preconcurrency @testable import FlowDown
import Foundation
import ListViewKit
import Storage
import Testing
import UIKit

/// A list that rests on its end stays on it when its size changes. At a new
/// width every row is measured again, the ones on screen in the layout pass
/// and the rest a few at a time after it, and the end moves with each.
@Suite(.serialized)
struct MessageListFollowEndTests {
    private static func reply(_ index: Int, paragraphs: Int) -> String {
        (0 ..< paragraphs).map {
            "Reply \(index), paragraph \($0), which goes on with `code`, **bold** text and enough words to wrap onto more lines the narrower the list gets."
        }.joined(separator: "\n\n")
    }

    /// A list in a window on the end of a conversation several screens long.
    @MainActor
    private func withListAtItsEnd(
        size: CGSize = CGSize(width: 700, height: 600),
        _ body: @MainActor (MessageListView) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Follow End \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let entries: [MessageListView.Entry] = (0 ..< 12).map { index in
            let message = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: Self.reply(index, paragraphs: 6 + index % 5))
            }
            let representation = MessageListView.MessageRepresentation(from: message)
            return .aiContent(representation.id, representation)
        }

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.isHidden = false
        defer { window.isHidden = true }
        let list = MessageListView()
        list.frame = window.bounds
        window.addSubview(list)
        list.layoutIfNeeded()
        list.listView.apply(entries)
        list.listView.landOnEnd()
        list.layoutIfNeeded()
        try await rest(list)
        #expect(distanceFromEnd(list) <= 2)
        try await body(list)
    }

    @MainActor
    private func distanceFromEnd(_ list: MessageListView) -> CGFloat {
        abs(list.listView.maximumContentOffset.y - list.listView.contentOffset.y)
    }

    /// Waits until the list has neither scrolled nor changed height for a
    /// while: it scrolls with a spring and goes on measuring rows after a
    /// width change.
    @MainActor
    private func rest(_ list: MessageListView, atMost seconds: TimeInterval = 8) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        var last: [CGFloat] = []
        var still = 0
        while still < 4, Date() < deadline {
            try await Task.sleep(for: .milliseconds(120))
            let now = [list.listView.contentOffset.y, list.listView.contentSize.height]
            still = now == last ? still + 1 : 0
            last = now
        }
    }

    @Test
    @MainActor
    func `a list on its end is on its end again after it gets narrower in one step`() async throws {
        try await withListAtItsEnd { list in
            let height = list.listView.contentSize.height
            list.frame.size.width = 380
            list.layoutIfNeeded()
            try await rest(list)
            // Narrower, the conversation is taller, and the rows on screen grew
            // in the very pass that made it so.
            #expect(list.listView.contentSize.height > height + 200)
            #expect(distanceFromEnd(list) <= 2)
        }
    }

    @Test
    @MainActor
    func `a list on its end is on its end again after it gets wider and narrower in turn`() async throws {
        try await withListAtItsEnd(size: CGSize(width: 420, height: 600)) { list in
            for width: CGFloat in [760, 400, 620, 360] {
                list.frame.size.width = width
                list.layoutIfNeeded()
                try await rest(list)
                #expect(distanceFromEnd(list) <= 2, "at width \(width)")
            }
        }
    }

    @Test
    @MainActor
    func `a list on its end is on its end again after it gets shorter, as when a keyboard comes up`() async throws {
        try await withListAtItsEnd { list in
            list.frame.size.height = 320
            list.layoutIfNeeded()
            try await rest(list)
            #expect(distanceFromEnd(list) <= 2)
        }
    }

    /// A reader who dragged away from the end is left where they are.
    @Test
    @MainActor
    func `a list its reader scrolled away from the end is not sent there by a width change`() async throws {
        try await withListAtItsEnd { list in
            let listView = list.listView
            list.scrollViewWillBeginDragging(listView)
            listView.contentOffset = CGPoint(x: 0, y: (listView.maximumContentOffset.y / 2).rounded())
            listView.layoutIfNeeded()
            list.frame.size.width = 380
            list.layoutIfNeeded()
            try await rest(list)
            #expect(distanceFromEnd(list) > 400)
        }
    }
}

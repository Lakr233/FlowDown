@preconcurrency @testable import FlowDown
import Foundation
import ListViewKit
import Storage
import Testing
import UIKit

/// The list makes the replies a few screens on ready while it stands still,
/// so that scrolling to one only uncovers it. On every platform: a phone
/// builds a reply no faster than a Mac does.
@Suite(.serialized)
struct MessageListPreparationTests {
    private static func reply(_ index: Int, paragraphs: Int) -> String {
        (0 ..< paragraphs).map {
            "Reply \(index), paragraph \($0), with `code`, **bold** text and enough words to wrap onto another line."
        }.joined(separator: "\n\n")
    }

    @Test
    @MainActor
    func `the list keeps rows ready three screens ahead and one behind`() {
        #expect(MessageListView().listView.preparationRange == .viewports(ahead: 3, behind: 1))
    }

    @Test
    @MainActor
    func `replies past the screen are mounted while the list stands still`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Preparation \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let entries: [MessageListView.Entry] = (0 ..< 16).map { index in
            let message = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: Self.reply(index, paragraphs: 6 + index % 3))
            }
            let representation = MessageListView.MessageRepresentation(from: message)
            return .aiContent(representation.id, representation)
        }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 500))
        window.isHidden = false
        defer { window.isHidden = true }
        let list = MessageListView()
        list.frame = window.bounds
        window.addSubview(list)
        list.layoutIfNeeded()
        let listView = list.listView
        listView.apply(entries)
        listView.landOnEnd()
        list.layoutIfNeeded()

        // Opened on its end, the list has only what the screen shows and is read
        // upwards from there. Every other row is an estimate until it is
        // measured, a few between frames, and the rows above the screen are
        // made ready the same way: wait for both to be done.
        var last: [CGFloat] = []
        var still = 0
        let deadline = Date().addingTimeInterval(15)
        while still < 5, Date() < deadline {
            try await Task.sleep(for: .milliseconds(120))
            // A pass lets go of the rows the first one mounted when every height
            // was an estimate and a screen held most of the conversation.
            listView.setNeedsLayout()
            listView.layoutIfNeeded()
            let now = [listView.contentSize.height, CGFloat(listView.visibleRowViews.count)]
            still = now == last ? still + 1 : 0
            last = now
        }
        let screen = listView.bounds.height
        #expect(listView.contentSize.height > screen * 6)
        #expect(abs(listView.maximumContentOffset.y - listView.contentOffset.y) <= 2)
        let top = listView.visibleRowViews.map(\.frame.minY).min() ?? listView.bounds.minY
        // Three screens ahead is the range; a row is whole or not there, so two
        // is what can be counted on.
        #expect(listView.bounds.minY - top >= screen * 2)
    }
}

@preconcurrency @testable import FlowDown
import Foundation
import ListViewKit
import Litext
import MarkdownView
import Storage
import Testing
import UIKit

/// A reply many screens tall draws its text in tiles around what the list
/// shows. The reader has to find text wherever the list takes them, and a
/// picture of the reply has to hold all of it.
@Suite(.serialized)
struct MessageListTiledReplyTests {
    private static func reply(paragraphs: Int) -> String {
        (0 ..< paragraphs).map {
            "Paragraph \($0) of a reply that goes on, with `code`, **bold** text and enough words to wrap onto another line at any width a list has."
        }.joined(separator: "\n\n")
    }

    /// A list in a window showing a short reply, a long one and another short
    /// one, its replies made with `tiling`.
    @MainActor
    private func withList(
        tiling: TextLabelView.TiledDrawing?,
        paragraphs: Int,
        size: CGSize = CGSize(width: 600, height: 700),
        _ body: @MainActor (MessageListView, MessageListView.Entry, _ makeReply: (String) -> MessageListView.Entry) throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let setting = ChatMarkdownView.tiledDrawing
        defer { ChatMarkdownView.tiledDrawing = setting }
        ChatMarkdownView.tiledDrawing = tiling

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Tiled Reply \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        func entry(_ text: String) -> MessageListView.Entry {
            let message = session.appendNewMessage(role: .assistant) {
                $0.update(\.document, to: text)
            }
            let representation = MessageListView.MessageRepresentation(from: message)
            return .aiContent(representation.id, representation)
        }
        let entries = [
            entry("A short reply before it."),
            entry(Self.reply(paragraphs: paragraphs)),
            entry("A short reply after it."),
        ]

        let window = UIWindow(frame: CGRect(origin: .zero, size: size))
        window.isHidden = false
        defer { window.isHidden = true }
        let list = MessageListView()
        list.frame = window.bounds
        window.addSubview(list)
        list.layoutIfNeeded()
        // A reader's list: once dragged it stays where it is put.
        list.scrollViewWillBeginDragging(list.listView)
        list.listView.apply(entries)
        list.listView.layoutIfNeeded()
        try body(list, entries[1], entry)
    }

    @MainActor
    private func label(of entry: MessageListView.Entry, in list: MessageListView) throws -> TextLabelView {
        let row = try #require(list.listView.rowView(for: entry.id) as? AiMessageView)
        return row.markdownView.textLabelView
    }

    /// The frames of the label's tiles, top to bottom. Litext keeps them as
    /// sublayers of the label's layer, of a class it does not make public.
    @MainActor
    private func tiles(of label: TextLabelView) -> [CGRect] {
        (label.layer.sublayers ?? [])
            .filter { String(describing: type(of: $0)) == "TextLabelTileLayer" }
            .map(\.frame)
            .sorted { $0.minY < $1.minY }
    }

    /// The part of the label the list shows that no tile lies under.
    @MainActor
    private func uncovered(_ label: TextLabelView, in list: MessageListView) -> CGFloat {
        let shown = label.convert(list.listView.bounds, from: list.listView).intersection(label.bounds)
        guard !shown.isNull, shown.height > 0 else { return 0 }
        var covered = shown.minY
        for frame in tiles(of: label) where frame.minY <= covered + 0.01 {
            covered = max(covered, frame.maxY)
        }
        return max(0, shown.maxY - covered)
    }

    @MainActor
    private func scroll(_ list: MessageListView, to y: CGFloat) {
        let listView = list.listView
        let target = min(max(listView.minimumContentOffset.y, y.rounded()), listView.maximumContentOffset.y)
        listView.contentOffset = CGPoint(x: 0, y: target)
        listView.layoutIfNeeded()
    }

    @Test
    @MainActor
    func `a long reply is drawn in tiles, and wherever the list jumps tiles lie under what it shows`() async throws {
        try await withList(tiling: ChatMarkdownView.tiledDrawing, paragraphs: 140) { list, entry, _ in
            let rect = list.listView.rectForRow(at: 1)
            #expect(rect.height > 4096)
            let offsets = [
                rect.minY - 200, rect.minY + 900, rect.midY, rect.maxY - 300,
                rect.minY + 2600, rect.minY + 40, rect.maxY - 700,
            ]
            for offset in offsets {
                scroll(list, to: offset)
                let label = try label(of: entry, in: list)
                #expect(label.bounds.height > 4096)
                let tiles = tiles(of: label)
                #expect(!tiles.isEmpty, "no tiles at \(offset)")
                // Around the window, not the whole reply.
                #expect(tiles.count < Int(label.bounds.height / 512))
                #expect(uncovered(label, in: list) == 0, "at \(offset)")
            }
        }
    }

    /// The list moves a row without scrolling when it measures the rows above
    /// it again, and a reply has no way to know. The list tells it
    /// (`AiMessageView.updateTilesAfterListLayout`).
    @Test
    @MainActor
    func `tiles follow a reply the list moves when its width changes`() async throws {
        try await withList(tiling: ChatMarkdownView.tiledDrawing, paragraphs: 140) { list, entry, _ in
            scroll(list, to: list.listView.rectForRow(at: 1).midY)
            #expect(try uncovered(label(of: entry, in: list), in: list) == 0)
            for width: CGFloat in [380, 600, 450, 320] {
                list.frame.size.width = width
                list.layoutIfNeeded()
                list.listView.layoutIfNeeded()
                let label = try label(of: entry, in: list)
                #expect(label.bounds.height > 4096)
                #expect(!tiles(of: label).isEmpty)
                #expect(uncovered(label, in: list) == 0, "at width \(width)")
            }
        }
    }

    /// A label looks for the part of it on screen in its own layout pass. The
    /// list asks for one whenever it has placed its rows, so the tiles are made
    /// in the frame that shows the reply where it now is.
    @Test
    @MainActor
    func `the list has a tiled reply on screen look again each time it lays its rows out`() async throws {
        try await withList(tiling: ChatMarkdownView.tiledDrawing, paragraphs: 140) { list, entry, _ in
            scroll(list, to: list.listView.rectForRow(at: 1).midY)
            let label = try label(of: entry, in: list)
            label.layoutIfNeeded()
            #expect(!label.layer.needsLayout())
            list.listView.layoutContent()
            #expect(label.layer.needsLayout())
        }
    }

    /// Rows above a reply that change height move it by as much, and the list
    /// moves its offset with them so that the reader sees the same text. Neither
    /// is a scroll the reply would notice by itself in time.
    @Test
    @MainActor
    func `tiles follow a reply the list moves when the rows above it change`() async throws {
        try await withList(tiling: ChatMarkdownView.tiledDrawing, paragraphs: 140) { list, entry, makeReply in
            let listView = list.listView
            scroll(list, to: listView.rectForRow(at: 1).midY)
            let before = listView.rectForRow(at: 1).minY
            let after = listView.content[2]
            for paragraphs in [80, 1, 200] {
                listView.apply([makeReply(Self.reply(paragraphs: paragraphs)), entry, after])
                listView.layoutIfNeeded()
                let label = try label(of: entry, in: list)
                #expect(!tiles(of: label).isEmpty)
                #expect(uncovered(label, in: list) == 0, "with \(paragraphs) paragraphs above")
            }
            #expect(listView.rectForRow(at: 1).minY != before)
        }
    }

    @Test
    @MainActor
    func `a reply below the height that tiles start at keeps one bitmap`() async throws {
        try await withList(tiling: ChatMarkdownView.tiledDrawing, paragraphs: 12) { list, entry, _ in
            scroll(list, to: list.listView.rectForRow(at: 1).minY)
            let label = try label(of: entry, in: list)
            #expect(label.bounds.height < 4096)
            #expect(tiles(of: label).isEmpty)
        }
    }

    private struct Picture: Equatable {
        var width = 0
        var height = 0
        var pixels = Data()

        /// Where and by how much two pictures of one size differ.
        func describeDifference(from other: Picture) -> String {
            guard pixels.count == other.pixels.count, height > 0 else { return "sizes differ" }
            let bytesPerRow = width * 4
            var bytes = 0
            var worst = 0
            var firstRow = -1
            var lastRow = -1
            for index in 0 ..< pixels.count where pixels[index] != other.pixels[index] {
                bytes += 1
                worst = max(worst, abs(Int(pixels[index]) - Int(other.pixels[index])))
                let row = index / bytesPerRow
                if firstRow < 0 { firstRow = row }
                lastRow = row
            }
            return "\(bytes) bytes differ by up to \(worst), in rows \(firstRow)...\(lastRow) of \(height)"
        }

        /// Rows that hold a pixel unlike the picture's first: text, in a picture
        /// of text on a plain ground.
        func inkedRows(in rows: Range<Int>) -> Int {
            guard width > 0, pixels.count >= 4 else { return 0 }
            let bytesPerRow = width * 4
            let ground = Array(pixels.prefix(4))
            return rows.count(where: { row in
                let start = row * bytesPerRow
                return stride(from: start, to: start + width * 4, by: 4).contains { offset in
                    !pixels[offset ..< offset + 4].elementsEqual(ground)
                }
            })
        }
    }

    /// The image's pixels as eight-bit RGBA. A renderer keeps a picture that
    /// turned out to hold no color in fewer bytes, so two pictures of the same
    /// thing need not be stored the same way.
    private static func picture(_ image: UIImage) throws -> Picture {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width, height = cgImage.height
        var pixels = Data(count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue,
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        try #require(drawn)
        return Picture(width: width, height: height, pixels: pixels)
    }

    /// Copy as Image renders the row's layer. A reply drawn in tiles has drawn
    /// only what is near the window; its picture has to be the whole reply all
    /// the same, pixel for pixel what one bitmap gives.
    @Test
    @MainActor
    func `the picture Copy as Image makes of a tiled reply is the one a whole bitmap gives`() async throws {
        func copied(tiling: TextLabelView.TiledDrawing?) async throws -> Picture {
            var result = Picture()
            try await withList(tiling: tiling, paragraphs: 40, size: CGSize(width: 360, height: 500)) { list, entry, _ in
                // The middle of the reply on screen: its top and its end are
                // far from any tile.
                scroll(list, to: list.listView.rectForRow(at: 1).midY)
                let label = try label(of: entry, in: list)
                #expect(label.bounds.height > 2000)
                #expect(tiles(of: label).isEmpty == (tiling == nil))
                let row = try #require(list.listView.rowView(for: entry.id))
                result = try Self.picture(MessageListView.image(ofRow: row))
            }
            return result
        }
        let tiled = try await copied(tiling: .init(threshold: 600))
        let whole = try await copied(tiling: nil)
        #expect(tiled.width == whole.width)
        #expect(tiled.height == whole.height)
        #expect(tiled == whole, "\(tiled.describeDifference(from: whole))")
        // Text from the top of the picture to its end.
        let band = tiled.height / 8
        #expect(tiled.inkedRows(in: 0 ..< band) > 10)
        #expect(tiled.inkedRows(in: tiled.height / 2 ..< tiled.height / 2 + band) > 10)
        #expect(tiled.inkedRows(in: tiled.height - band ..< tiled.height) > 10)
    }

    /// Save Image lays the conversation out beside the window, where a tiled
    /// reply has no tiles at all, and renders that.
    @Test
    @MainActor
    func `the picture Save Image makes of a conversation holds the whole of a tiled reply`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let setting = ChatMarkdownView.tiledDrawing
        defer { ChatMarkdownView.tiledDrawing = setting }

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Saved Reply \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        session.appendNewMessage(role: .user) {
            $0.update(\.document, to: "Write it all out.")
        }
        session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: Self.reply(paragraphs: 30))
        }
        session.notifyMessagesDidChange()

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 700))
        let controller = UIViewController()
        window.rootViewController = controller
        window.isHidden = false
        defer { window.isHidden = true }
        window.layoutIfNeeded()

        func saved(tiling: TextLabelView.TiledDrawing?) async throws -> Picture {
            ChatMarkdownView.tiledDrawing = tiling
            let view = ConversationCaptureView(session: session, preset: .small)
            let image = await withCheckedContinuation { continuation in
                view.capture(controller: controller) { image in
                    continuation.resume(returning: image)
                }
            }
            var tall = 0
            var queue: [UIView] = [view]
            while let next = queue.popLast() {
                queue.append(contentsOf: next.subviews)
                if let label = next as? TextLabelView, label.bounds.height > 600 {
                    tall += 1
                    // Laid out beside the window, a tiled reply keeps no tile and
                    // has no bitmap of its own either.
                    #expect(tiles(of: label).isEmpty)
                    #expect(label.tiledDrawing == tiling)
                }
            }
            #expect(tall == 1)
            return try Self.picture(#require(image))
        }
        let tiled = try await saved(tiling: .init(threshold: 600))
        let whole = try await saved(tiling: nil)
        #expect(tiled.height > 1500)
        #expect(tiled == whole, "\(tiled.describeDifference(from: whole))")
        let band = tiled.height / 8
        #expect(tiled.inkedRows(in: tiled.height / 2 ..< tiled.height / 2 + band) > 10)
        #expect(tiled.inkedRows(in: tiled.height - 3 * band ..< tiled.height - 2 * band) > 10)
    }
}

@preconcurrency @testable import FlowDown
import Foundation
import MarkdownParser
import MarkdownView
import Storage
import Testing
import UIKit

@Suite(.serialized)
struct MarkdownSizingViewPoolTests {
    private let markdown = """
    Some **bold** text and a [link](https://example.com) that has to wrap when
    the container gets narrow enough to break the line.

    - first item
    - second item

    ```swift
    let value = 42
    ```

    A closing paragraph so the document has more than one block to stack.
    """


    @MainActor
    private func withMessage(
        _ text: String,
        _ body: @MainActor (MessageListView.MessageRepresentation, Message) throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Sizing Pool \(UUID().uuidString.prefix(8))")
        }
        defer { ConversationManager.shared.deleteConversation(identifier: conversation.id) }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        let message = session.appendNewMessage(role: .assistant) {
            $0.update(\.document, to: text)
        }
        try body(.init(from: message), message)
    }

    @MainActor
    private func content(_ text: String, theme: MarkdownTheme) -> MarkdownContent {
        MarkdownContent(repairing: MarkdownParser().parse(text), theme: theme)
    }

    @MainActor
    private func referenceHeight(_ text: String, theme: MarkdownTheme, width: CGFloat) -> CGFloat {
        // What the pool replaced: a view that gets the content installed and is
        // thrown away again for every single measurement.
        let view = MarkdownTextView()
        view.theme = theme
        view.setContentImmediately(content(text, theme: theme))
        let height = view.boundingSize(for: width).height
        view.reset()
        return height
    }

    @Test
    @MainActor
    func `pooled measurements match a freshly built view at every width`() async throws {
        try await withMessage(markdown) { message, _ in
            let theme = MarkdownTheme.default
            let pool = MessageListView.MarkdownSizingViewPool()
            for width in stride(from: CGFloat(220), through: 520, by: 20) {
                let pooled = pool.view(for: message, theme: theme) { self.content(self.markdown, theme: theme) }
                    .boundingSize(for: width).height
                let reference = self.referenceHeight(self.markdown, theme: theme, width: width)
                #expect(abs(pooled - reference) < 0.5, "width \(width): \(pooled) vs \(reference)")
            }
        }
    }

    @Test
    @MainActor
    func `a width only change reuses the view instead of rebuilding it`() async throws {
        try await withMessage(markdown) { message, _ in
        let theme = MarkdownTheme.default
        let pool = MessageListView.MarkdownSizingViewPool()

        var buildCount = 0
        let build = { @MainActor in
            buildCount += 1
            return self.content(self.markdown, theme: theme)
        }

        let first = pool.view(for: message, theme: theme, content: build)
        _ = first.boundingSize(for: 300)
        let second = pool.view(for: message, theme: theme, content: build)
        _ = second.boundingSize(for: 420)

        #expect(first === second)
        #expect(buildCount == 1)
        }
    }

    @Test
    @MainActor
    func `changed content and changed theme both rebuild`() async throws {
        try await withMessage(markdown) { representation, _ in
        let theme = MarkdownTheme.default
        let pool = MessageListView.MarkdownSizingViewPool()
        var message = representation

        var buildCount = 0
        let build: @MainActor (String, MarkdownTheme) -> MarkdownContent = { text, buildTheme in
            buildCount += 1
            return self.content(text, theme: buildTheme)
        }

        _ = pool.view(for: message, theme: theme) { build(self.markdown, theme) }
        #expect(buildCount == 1)

        message.content = markdown + "\n\nOne more paragraph."
        _ = pool.view(for: message, theme: theme) { build(message.content, theme) }
        #expect(buildCount == 2)

        var otherTheme = theme
        otherTheme.fonts.body = .systemFont(ofSize: theme.fonts.body.pointSize + 3)
        _ = pool.view(for: message, theme: otherTheme) { build(message.content, otherTheme) }
        #expect(buildCount == 3)
        }
    }
}

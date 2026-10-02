@preconcurrency @testable import FlowDown
import Foundation
import MarkdownView
import Storage
import Testing
import UIKit

struct MarkdownPackageCacheTests {
    @MainActor
    private func representation(_ text: String) -> MessageListView.MessageRepresentation {
        let message = Message(deviceId: "MarkdownPackageCacheTests")
        message.update(\.role, to: .assistant)
        message.update(\.document, to: text)
        return .init(from: message)
    }

    @Test
    @MainActor
    func package_sameContentAndTheme_reusesContent() {
        let message = representation("Inline math $x^2$ next to body text.")
        let cache = MessageListView.MarkdownPackageCache()
        let theme = MarkdownTheme.default

        let first = cache.package(for: message, theme: theme)
        let second = cache.package(for: message, theme: theme)

        #expect(first === second)
    }

    @Test
    @MainActor
    func package_themeChange_rebuildsContent() {
        // Math images are rendered at the body size when the content is built,
        // so a Font Size change has to produce new content for unchanged text.
        let message = representation("Inline math $x^2$ next to body text.")
        let cache = MessageListView.MarkdownPackageCache()
        let theme = MarkdownTheme.default

        let original = cache.package(for: message, theme: theme)

        var scaledTheme = theme
        scaledTheme.fonts.body = .systemFont(ofSize: theme.fonts.body.pointSize + 4)
        let scaled = cache.package(for: message, theme: scaledTheme)

        #expect(scaled !== original)
        #expect(cache.package(for: message, theme: scaledTheme) === scaled)
        #expect(cache.package(for: message, theme: theme) !== scaled)
    }
}

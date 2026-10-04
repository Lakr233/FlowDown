//
//  Created by ktiays on 2025/2/11.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import MarkdownParser
import MarkdownView
import Storage
import UIKit

extension MessageListView {
    final class MarkdownPackageCache {
        typealias MessageIdentifier = Message.ID

        /// Math images are rendered at the theme's body size when the content is
        /// built, so an entry only stays valid for the theme it was built with.
        private struct Entry {
            let contentHash: Int
            let isStreaming: Bool
            let theme: MarkdownTheme
            let content: MarkdownContent
        }

        private var cache: [MessageIdentifier: Entry] = [:]
        private let lock = NSLock()

        func package(for message: MessageRepresentation, theme: MarkdownTheme) -> MarkdownContent {
            let id = message.id
            let contentHash = message.content.hashValue

            lock.lock()
            if let entry = cache[id],
               entry.contentHash == contentHash,
               entry.isStreaming == message.isStreaming,
               entry.theme == theme
            {
                lock.unlock()
                return entry.content
            }
            lock.unlock()

            return updateCache(for: message, theme: theme, contentHash: contentHash)
        }

        private func makeContent(
            result: MarkdownParser.ParseResult,
            theme: MarkdownTheme,
        ) -> MarkdownContent {
            let work = { @MainActor in
                MarkdownContent(repairing: result, theme: theme)
            }
            if Thread.isMainThread {
                return MainActor.assumeIsolated { work() }
            } else {
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated { work() }
                }
            }
        }

        private func updateCache(
            for message: MessageRepresentation,
            theme: MarkdownTheme,
            contentHash: Int
        ) -> MarkdownContent {
            // A reply still being written has its unfinished end closed before
            // parsing, so half-typed markers do not flicker; the finished reply
            // is parsed again without it and lands on exactly what it says.
            let result = MarkdownParser().parse(message.content, isStreaming: message.isStreaming)
            let package = makeContent(result: result, theme: theme)

            lock.lock()
            cache[message.id] = .init(
                contentHash: contentHash,
                isStreaming: message.isStreaming,
                theme: theme,
                content: package,
            )
            lock.unlock()

            return package
        }
    }
}

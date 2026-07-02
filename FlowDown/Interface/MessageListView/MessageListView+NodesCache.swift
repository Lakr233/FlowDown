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

        private var cache: [MessageIdentifier: MarkdownContent] = [:]
        private var messageDidChanged: [MessageIdentifier: Int] = [:]
        private let lock = NSLock()

        func package(for message: MessageRepresentation, theme: MarkdownTheme) -> MarkdownContent {
            let id = message.id
            let contentHash = message.content.hashValue

            lock.lock()
            if let cachedHash = messageDidChanged[id],
               cachedHash == contentHash,
               let nodes = cache[id]
            {
                lock.unlock()
                return nodes
            }
            lock.unlock()

            return updateCache(for: message, theme: theme, contentHash: contentHash)
        }

        private func renderOnMain(
            result: MarkdownParser.ParseResult,
            theme: MarkdownTheme,
        ) -> (RenderedTextContent.Map, [Int: CodeHighlighter.HighlightMap]) {
            let work = { @MainActor in
                let rendered: RenderedTextContent.Map = result.renderedContent(theme: theme)
                let highlights: [Int: CodeHighlighter.HighlightMap] = result.highlightMaps(theme: theme)
                return (rendered, highlights)
            }
            if Thread.isMainThread {
                return MainActor.assumeIsolated { work() }
            } else {
                return DispatchQueue.main.sync {
                    MainActor.assumeIsolated { work() }
                }
            }
        }

        private func updateCache(for message: MessageRepresentation, theme: MarkdownTheme, contentHash: Int) -> MarkdownContent {
            let content = message.content
            let result = MarkdownParser().parse(content)
            let blocks = result.documentByRepairingInlineMathPlaceholders()
            let (rendered, highlightMaps) = renderOnMain(result: result, theme: theme)
            let package = MarkdownContent(
                blocks: blocks,
                rendered: rendered,
                highlightMaps: highlightMaps,
            )

            lock.lock()
            cache[message.id] = package
            messageDidChanged[message.id] = contentHash
            lock.unlock()

            return package
        }
    }
}

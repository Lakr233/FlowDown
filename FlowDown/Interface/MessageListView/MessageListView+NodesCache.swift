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

        private var cache: [MessageIdentifier: MarkdownTextView.PreprocessedContent] = [:]
        private var messageDidChanged: [MessageIdentifier: Int] = [:]
        private let lock = NSLock()

        func package(for message: MessageRepresentation, theme: MarkdownTheme) -> MarkdownTextView.PreprocessedContent {
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

        private func updateCache(for message: MessageRepresentation, theme: MarkdownTheme, contentHash: Int) -> MarkdownTextView.PreprocessedContent {
            let content = message.content
            let result = MarkdownParser().parse(content)
            let blocks = result.documentByRepairingInlineMathPlaceholders()
            let rendered: RenderedTextContent.Map = result.render(theme: theme)
            let highlightMaps: [Int: CodeHighlighter.HighlightMap] = result.render(theme: theme)
            let package = MarkdownTextView.PreprocessedContent(
                blocks: blocks,
                rendered: rendered,
                highlightMaps: highlightMaps
            )

            lock.lock()
            cache[message.id] = package
            messageDidChanged[message.id] = contentHash
            lock.unlock()

            return package
        }
    }
}

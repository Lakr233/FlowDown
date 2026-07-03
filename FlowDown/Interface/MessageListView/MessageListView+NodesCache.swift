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

        private func updateCache(for message: MessageRepresentation, theme: MarkdownTheme, contentHash: Int) -> MarkdownContent {
            let content = message.content
            let result = MarkdownParser().parse(content)
            let package = makeContent(result: result, theme: theme)

            lock.lock()
            cache[message.id] = package
            messageDidChanged[message.id] = contentHash
            lock.unlock()

            return package
        }
    }
}

//
//  MessageListView+SizingViewPool.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/9/26.
//

import MarkdownView
import Storage
import UIKit

extension MessageListView {
    /// Off-screen views kept around purely to measure row heights.
    ///
    /// Changing the list width turns every measured height back into an estimate,
    /// so each visible row is measured again. Installing content into a view is
    /// what makes that expensive: it rebuilds the CoreText framesetter, and half
    /// of that is CoreText resolving a composition language through the bundle's
    /// localizations. None of it depends on the width.
    ///
    /// Holding one view per row means a width-only change reframes what is
    /// already built. The content itself is only reinstalled when the message or
    /// the theme actually changes.
    final class MarkdownSizingViewPool {
        private struct Entry {
            let view: MarkdownTextView
            let contentHash: Int
            let theme: MarkdownTheme
        }

        /// Enough to cover the rows a viewport can show at once with room to
        /// spare, while keeping the context views these hold on to bounded.
        private let limit = 24

        private var entries: [Message.ID: Entry] = [:]
        private var recentlyUsed: [Message.ID] = []

        /// Returns a view already holding this message's content at this theme,
        /// building it only when something other than the width changed.
        func view(
            for message: MessageRepresentation,
            theme: MarkdownTheme,
            content: () -> MarkdownContent,
        ) -> MarkdownTextView {
            let contentHash = message.content.hashValue
            if let entry = entries[message.id],
               entry.contentHash == contentHash,
               entry.theme == theme
            {
                touch(message.id)
                return entry.view
            }

            let view = entries[message.id]?.view ?? MarkdownTextView()
            // Assigning the theme reinstalls the current content, so it goes
            // first while the view is still empty or already stale.
            view.theme = theme
            view.setContentImmediately(content())
            entries[message.id] = .init(view: view, contentHash: contentHash, theme: theme)
            touch(message.id)
            evictIfNeeded()
            return view
        }

        func removeAll() {
            for entry in entries.values { entry.view.reset() }
            entries.removeAll()
            recentlyUsed.removeAll()
        }

        private func touch(_ identifier: Message.ID) {
            if let index = recentlyUsed.firstIndex(of: identifier) {
                recentlyUsed.remove(at: index)
            }
            recentlyUsed.append(identifier)
        }

        private func evictIfNeeded() {
            while recentlyUsed.count > limit {
                let identifier = recentlyUsed.removeFirst()
                // Emptying the view lets it hand back the code and table views it
                // borrowed instead of holding them for a row nobody measures.
                entries.removeValue(forKey: identifier)?.view.reset()
            }
        }
    }
}

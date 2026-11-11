//
//  MessageListView+InlineSteps.swift
//  FlowDown
//

import Foundation
import Storage

extension MessageListView {
    /// The reason each call gave, decoded from its row once. Summaries that
    /// list their steps (`InlineActivityStepsSetting`) show every call's
    /// reason, and the entries are built again on every streamed chunk;
    /// decoding a call's stored request each time is what this saves.
    ///
    /// A row's request is written once, right after the row is made, so the
    /// size of its metadata is enough to tell a decoded request from a later
    /// one. Entries are built on the update queue and on the main queue.
    final class ToolReasonCache: @unchecked Sendable {
        private struct Record {
            let metadataSize: Int
            let reason: String?
        }

        private let lock = NSLock()
        private var records: [Message.ID: Record] = [:]
        /// Past this many rows the cache starts again.
        private let capacity = 512

        /// `decode`: the call's arguments as JSON, nil when it has none.
        func reason(for message: Message, decode: (Message) -> String?) -> String? {
            let size = message.metadata?.count ?? 0
            lock.lock()
            let record = records[message.objectId]
            lock.unlock()
            if let record, record.metadataSize == size {
                return record.reason
            }
            let reason = decode(message).flatMap(ModelToolReason.reason(in:))
            lock.lock()
            if records.count >= capacity {
                records.removeAll()
            }
            records[message.objectId] = Record(metadataSize: size, reason: reason)
            lock.unlock()
            return reason
        }
    }

    /// Holds back a listed thought's text while it streams, so the row grows
    /// a few times a second instead of on every chunk: each new text is
    /// typeset and measured again. The first text of a thought, a text that
    /// is not the shown one grown, and every thought of a summary no longer
    /// running pass at once. Confined to the update queue.
    struct InlineThoughtThrottle {
        static let interval: TimeInterval = 0.2

        private var shown: [String: (text: String, time: TimeInterval)] = [:]

        /// Puts the text last shown back into the running summaries' thoughts
        /// that grew within `interval` of it. Returns how long until the
        /// newest of what was held back may show, nil when nothing was.
        mutating func apply(to entries: inout [Entry], now: TimeInterval) -> TimeInterval? {
            var wait: TimeInterval?
            var seen: Set<String> = []
            for index in entries.indices {
                guard case var .activity(summary) = entries[index],
                      summary.showsSteps,
                      summary.isRunning
                else { continue }
                var held = false
                for stepIndex in summary.steps.indices {
                    let step = summary.steps[stepIndex]
                    guard case let .thought(messageID, text) = step else { continue }
                    seen.insert(step.id)
                    guard let last = shown[step.id], last.text != text else {
                        if shown[step.id] == nil {
                            shown[step.id] = (text, now)
                        }
                        continue
                    }
                    let elapsed = now - last.time
                    if elapsed < Self.interval, text.hasPrefix(last.text) {
                        summary.steps[stepIndex] = .thought(messageID, text: last.text)
                        held = true
                        let remaining = Self.interval - elapsed
                        wait = min(wait ?? remaining, remaining)
                    } else {
                        shown[step.id] = (text, now)
                    }
                }
                if held {
                    entries[index] = .activity(summary)
                }
            }
            shown = shown.filter { seen.contains($0.key) }
            return wait
        }
    }
}

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

    /// The list as the update queue last built it with listed steps, kept
    /// to show a held-back thought's text once it may (`InlineThoughtThrottle`).
    ///
    /// It holds the entries built when the notification came, which are
    /// values, never the `Message` objects they were built from: those are
    /// still being written by the turn's stream, so a flush that read them
    /// later would read them outside any notification. A flush shows what
    /// the last notification brought; anything newer comes with the next.
    /// Confined to the update queue.
    struct InlineStepsUpstream {
        struct Snapshot {
            /// As built from the messages, before the throttle.
            let entries: [Entry]
            let scrolling: Bool
            let isLoading: String?
        }

        private var throttle = InlineThoughtThrottle()
        private(set) var last: Snapshot?

        /// A notification's entries, captured: what to show of them, and
        /// how long until a held-back thought may show.
        mutating func receive(_ snapshot: Snapshot, now: TimeInterval) -> (entries: [Entry], wait: TimeInterval?) {
            last = snapshot
            var entries = snapshot.entries
            let wait = throttle.apply(to: &entries, now: now)
            return (entries, wait)
        }

        /// The last notification's entries once more, for a flush; nil when
        /// there are none to show.
        mutating func flush(now: TimeInterval) -> (snapshot: Snapshot, entries: [Entry], wait: TimeInterval?)? {
            guard let last else { return nil }
            let shown = receive(last, now: now)
            return (last, shown.entries, shown.wait)
        }

        /// With the setting off: nothing to flush.
        mutating func clear() {
            last = nil
        }

        /// A new session: nothing held back from the last one.
        mutating func reset() {
            self = .init()
        }
    }
}

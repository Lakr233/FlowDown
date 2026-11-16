//
//  DatabaseShrinkScheduler.swift
//  FlowDown
//

import Foundation
import Storage
import UIKit

/// Shrinks the database file once the app is in the background.
///
/// Every read and write of the database waits while the file is shrunk, and most of them are made on
/// the main thread. In the background nothing is on screen to wait for them. Coming back to the
/// foreground cancels a shrink that is still running, which leaves the file as it was.
@MainActor
enum DatabaseShrinkScheduler {
    private static var observers: [NSObjectProtocol] = []
    private static var current: Run?

    static func install() {
        guard observers.isEmpty else { return }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main,
            ) { _ in
                MainActor.assumeIsolated { begin() }
            },
            center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main,
            ) { _ in
                MainActor.assumeIsolated { current?.cancel() }
            },
        ]
    }

    private static func begin() {
        guard current == nil else { return }
        // a sync or a reply in progress is writing to the database
        guard !SyncEngine.isSynchronizing, !ConversationSessionManager.shared.hasExecutingSessions else { return }

        let run = Run()
        current = run
        run.backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "DatabaseShrink") {
            // out of background time: stop at the next batch of rows and let the app be suspended
            run.cancel()
            end(run)
        }

        let storage = sdb
        // Everything else that touches the database waits for this, so it is not run at a low priority.
        Task.detached(priority: .userInitiated) {
            storage.shrinkIfWorthwhile { !run.isCancelled }
            await MainActor.run {
                end(run)
                if current === run { current = nil }
            }
        }
    }

    private static func end(_ run: Run) {
        guard run.backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(run.backgroundTask)
        run.backgroundTask = .invalid
    }

    private final class Run: @unchecked Sendable {
        @MainActor var backgroundTask: UIBackgroundTaskIdentifier = .invalid

        private let lock = NSLock()
        private var cancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        func cancel() {
            lock.lock()
            cancelled = true
            lock.unlock()
        }
    }
}

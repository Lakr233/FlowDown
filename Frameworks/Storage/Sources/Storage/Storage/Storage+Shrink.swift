//
//  Storage+Shrink.swift
//  Storage
//

import Foundation
import OSLog
import WCDBSwift

// Deleting rows, or emptying their content, only marks pages of the database file as free. The file
// keeps its size. WCDB's vacuum copies the rows into a new file and puts it in place of the old one,
// and it closes the database for as long as that takes: every other read and write waits.
// So the shrink only runs when asked to, and only when it is worth it and looks safe.

public extension Storage {
    struct ShrinkPolicy: Sendable {
        /// The free pages have to add up to at least this many bytes,
        public var minimumReclaimableBytes: Int64 = 32 * 1024 * 1024
        /// and to at least this share of the file.
        public var minimumReclaimableFraction: Double = 0.25
        /// The copy needs room for the rows in use. The volume has to have this many times their size free.
        public var freeDiskFactor: Double = 2
        /// Reads and writes wait while the rows in use are copied, so a database with more than this is left alone.
        public var maximumLiveBytes: Int64 = 256 * 1024 * 1024
        /// The time to the next shrink after one that finished or failed.
        public var interval: TimeInterval = 60 * 60 * 24 * 3
        /// The time to the next shrink after one that was cancelled.
        public var intervalAfterCancel: TimeInterval = 60 * 60

        public init() {}
    }

    enum ShrinkSkipReason: String, Sendable {
        /// An export, an import or another shrink is running.
        case busy
        case tooSoon
        case notEnoughReclaimable
        case tooMuchLiveData
        case notEnoughFreeDisk
        case unableToMeasure
    }

    enum ShrinkResult: Equatable, Sendable {
        case shrunk(bytesBefore: Int64, bytesAfter: Int64)
        case skipped(ShrinkSkipReason)
        case cancelled
        case failed(String)
    }

    /// The pages of the database file, as SQLite counts them.
    struct DatabaseUsage: Equatable, Sendable {
        public var pageSize: Int64
        public var pageCount: Int64
        public var freePageCount: Int64

        public var totalBytes: Int64 { pageCount * pageSize }
        public var reclaimableBytes: Int64 { freePageCount * pageSize }
        public var liveBytes: Int64 { totalBytes - reclaimableBytes }
    }

    static let nextShrinkDateKey = "FlowdownStorageNextShrinkDate"

    func databaseUsage() throws -> DatabaseUsage {
        func value(_ pragma: Pragma, named name: String) throws -> Int64 {
            guard let value = try db.getValue(from: StatementPragma().pragma(pragma)) else {
                throw NSError(
                    domain: "Storage",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "No value for pragma \(name)"],
                )
            }
            return value.int64Value
        }
        return try DatabaseUsage(
            pageSize: value(.pageSize, named: "page_size"),
            pageCount: value(.pageCount, named: "page_count"),
            freePageCount: value(.freelistCount, named: "freelist_count"),
        )
    }

    /// Gives the free pages of the database file back to the disk, when the policy allows it.
    ///
    /// Call it off the main thread. It returns when the shrink is done, skipped, cancelled or failed.
    /// Every other read and write of this database waits until then.
    ///
    /// - Parameters:
    ///   - defaults: Where the date of the next allowed shrink is kept.
    ///   - shouldContinue: Asked between batches of rows. Returning false cancels the shrink, which
    ///     leaves the database file as it was.
    @discardableResult
    func shrinkIfWorthwhile(
        policy: ShrinkPolicy = .init(),
        defaults: UserDefaults = .standard,
        now: Date = .now,
        shouldContinue: @escaping @Sendable () -> Bool = { true },
    ) -> ShrinkResult {
        guard maintenanceGate.beginShrink() else { return .skipped(.busy) }
        defer { maintenanceGate.endShrink() }

        if let next = defaults.object(forKey: Storage.nextShrinkDateKey) as? Date,
           // a date further away than the interval was written with a clock that has since been set back
           now < next, next.timeIntervalSince(now) <= policy.interval
        {
            return .skipped(.tooSoon)
        }

        let before: DatabaseUsage
        do {
            before = try databaseUsage()
        } catch {
            Logger.database.errorFile("shrink unable to measure the database: \(error.localizedDescription)")
            return .skipped(.unableToMeasure)
        }
        guard before.reclaimableBytes >= policy.minimumReclaimableBytes,
              Double(before.reclaimableBytes) >= Double(before.totalBytes) * policy.minimumReclaimableFraction
        else {
            return .skipped(.notEnoughReclaimable)
        }
        guard before.liveBytes <= policy.maximumLiveBytes else {
            Logger.database.infoFile("shrink skipped, \(before.liveBytes) bytes in use is over the limit")
            return .skipped(.tooMuchLiveData)
        }
        guard let freeDisk = freeDiskBytes() else { return .skipped(.unableToMeasure) }
        guard Double(freeDisk) >= Double(before.liveBytes) * policy.freeDiskFactor else {
            Logger.database.infoFile("shrink skipped, \(freeDisk) bytes free for \(before.liveBytes) bytes in use")
            return .skipped(.notEnoughFreeDisk)
        }
        guard shouldContinue() else { return .cancelled }

        Logger.database.infoFile("shrink begin, \(before.totalBytes) bytes with \(before.reclaimableBytes) free")
        let cancelled = ShrinkCancellation()
        let begin = Date()
        do {
            try db.vacuum(with: { _, _ in
                if shouldContinue() { return true }
                cancelled.set()
                return false
            })
        } catch {
            let elapsed = Int(Date().timeIntervalSince(begin) * 1000)
            if cancelled.isSet {
                defaults.set(now.addingTimeInterval(policy.intervalAfterCancel), forKey: Storage.nextShrinkDateKey)
                Logger.database.infoFile("shrink cancelled after \(elapsed)ms")
                return .cancelled
            }
            defaults.set(now.addingTimeInterval(policy.interval), forKey: Storage.nextShrinkDateKey)
            Logger.database.errorFile("shrink failed after \(elapsed)ms: \(error.localizedDescription)")
            return .failed(error.localizedDescription)
        }
        defaults.set(now.addingTimeInterval(policy.interval), forKey: Storage.nextShrinkDateKey)

        let elapsed = Int(Date().timeIntervalSince(begin) * 1000)
        let bytesAfter = (try? databaseUsage().totalBytes) ?? -1
        Logger.database.infoFile("shrink end, \(before.totalBytes) to \(bytesAfter) bytes in \(elapsed)ms")
        return .shrunk(bytesBefore: before.totalBytes, bytesAfter: bytesAfter)
    }
}

extension Storage {
    func freeDiskBytes() -> Int64? {
        let values = try? databaseDir.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }
}

/// Keeps a shrink apart from an export and an import.
final class MaintenanceGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var isShrinking = false
    private var blockers = 0

    /// False when an export, an import or another shrink is running.
    func beginShrink() -> Bool {
        condition.lock()
        defer { condition.unlock() }
        guard !isShrinking, blockers == 0 else { return false }
        isShrinking = true
        return true
    }

    func endShrink() {
        condition.lock()
        isShrinking = false
        condition.broadcast()
        condition.unlock()
    }

    /// Waits for a running shrink to end, then keeps a new one from starting until `endBlocking`.
    func beginBlocking() {
        condition.lock()
        while isShrinking {
            condition.wait()
        }
        blockers += 1
        condition.unlock()
    }

    func endBlocking() {
        condition.lock()
        blockers -= 1
        condition.unlock()
    }
}

private final class ShrinkCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

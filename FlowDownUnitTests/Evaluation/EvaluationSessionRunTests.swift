//
//  EvaluationSessionRunTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import os
import Testing

struct EvaluationSessionRunTests {
    @Test
    func evaluationRun_stopDuringAttempt_leavesCasePendingWithoutRetrying() async throws {
        let session = makeSession(caseTitles: ["A"], shots: 2)
        let caseItem = try #require(session.allCases.first)
        let shotCount = OSAllocatedUnfairLock(initialState: 0)
        let entered = OSAllocatedUnfairLock(initialState: false)
        let released = OSAllocatedUnfairLock(initialState: false)
        session.singleShotOverride = { _ in
            shotCount.withLock { $0 += 1 }
            entered.withLock { $0 = true }
            while !released.withLock({ $0 }) {
                try? await Task.sleep(for: .milliseconds(5))
            }
            // A cancelled stream ends early, and its cut-off response scores as a failure.
            return .fail
        }

        session.resume()
        #expect(await waitUntil { entered.withLock { $0 } })

        // Leaving the status screen stops the run while the request is in flight.
        session.stopAndDispose(save: false)
        released.withLock { $0 = true }

        #expect(await waitUntil { caseItem.results.last?.outcome != .processing })
        #expect(shotCount.withLock { $0 } == 1)
        #expect(caseItem.results.last?.outcome == .notDetermined)

        await removeSavedSession(session)
    }

    @Test
    func evaluationRun_reRunDuringActiveRun_evaluatesCaseBeforeFinishing() async throws {
        let session = makeSession(caseTitles: ["A", "B"], shots: 1)
        let cases = session.allCases
        try #require(cases.count == 2)
        let caseA = cases[0]
        let caseB = cases[1]
        let shotCounts = OSAllocatedUnfairLock(initialState: [String: Int]())
        let releaseB = OSAllocatedUnfairLock(initialState: false)
        session.singleShotOverride = { caseItem in
            let title = caseItem.title
            shotCounts.withLock { $0[title, default: 0] += 1 }
            if title == "B" {
                while !releaseB.withLock({ $0 }) {
                    try? await Task.sleep(for: .milliseconds(5))
                }
                return .pass
            }
            return .fail
        }

        session.resume()
        // With one request at a time, A finishes first and B holds the run open.
        #expect(await waitUntil {
            caseA.results.last?.outcome == .fail && shotCounts.withLock { $0["B"] } == 1
        })

        // The same steps the Re-run menu action takes.
        let resultA = try #require(caseA.results.last)
        resultA.outcome = .notDetermined
        session.resume()
        releaseB.withLock { $0 = true }

        #expect(await waitUntil { !session.isRunning })
        #expect(shotCounts.withLock { $0["A"] } == 2)
        #expect(caseA.results.last?.outcome == .fail)
        #expect(caseB.results.last?.outcome == .pass)
        #expect(session.isCompleted)

        await removeSavedSession(session)
    }

    private func makeSession(caseTitles: [String], shots: Int) -> EvaluationSession {
        let cases = caseTitles.map { title in
            EvaluationManifest.Suite.Case(title: title, content: [], verifier: [])
        }
        let suite = EvaluationManifest.Suite(title: "Suite", description: "", cases: cases)
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite])
        return EvaluationSession(options: .init(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            options: .init(maxConcurrentRequests: 1, shots: shots),
        ))
    }

    private func waitUntil(
        timeout: Duration = .seconds(10),
        _ condition: () -> Bool,
    ) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return true
    }

    private func removeSavedSession(_ session: EvaluationSession) async {
        // A run saves the session as it goes; let the last debounced save land first.
        try? await Task.sleep(for: .seconds(1))
        try? EvaluationSessionManager.shared.delete(id: session.id)
    }
}

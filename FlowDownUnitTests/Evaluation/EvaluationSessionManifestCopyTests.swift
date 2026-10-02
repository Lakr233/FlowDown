//
//  EvaluationSessionManifestCopyTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import Testing

struct EvaluationSessionManifestCopyTests {
    @Test
    func evaluationSession_doesNotShareCasesAcrossSessions() throws {
        let options = EvaluationOptions(modelIdentifier: "test-model")
        let first = EvaluationSession(options: options)
        let firstCase = try #require(first.allCases.first)
        firstCase.results.append(.init(outcome: .pass))

        let second = EvaluationSession(options: options)
        let secondCase = try #require(second.allCases.first)
        let sourceCase = try #require(options.manifesets.first?.suites.first?.cases.first)

        #expect(second.allCases.allSatisfy { $0.results.isEmpty })
        #expect(sourceCase.results.isEmpty)
        #expect(firstCase !== secondCase)
        #expect(firstCase.id == secondCase.id)
        #expect(secondCase.id == sourceCase.id)
        // The copy must not prepend the test-environment instruction a second time.
        #expect(firstCase.content.count == secondCase.content.count)
        #expect(secondCase.content == sourceCase.content)
    }

    @Test
    func evaluationSession_startsWithoutResultsCarriedByImportedCases() throws {
        let caseItem = EvaluationManifest.Suite.Case(
            title: "A",
            content: [],
            verifier: [],
            results: [.init(outcome: .fail)],
        )
        let suite = EvaluationManifest.Suite(title: "Suite", description: "", cases: [caseItem])
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite])

        let session = EvaluationSession(options: .init(modelIdentifier: "test-model", manifesets: [manifest]))
        let sessionCase = try #require(session.allCases.first)

        #expect(sessionCase.results.isEmpty)
        #expect(sessionCase.id == caseItem.id)
        #expect(caseItem.results.count == 1)
    }
}

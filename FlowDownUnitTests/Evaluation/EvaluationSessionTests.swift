//
//  EvaluationSessionTests.swift
//  FlowDownUnitTests
//
//  Created by qaq on 18/12/2025.
//

@testable import ChatClientKit
@testable import FlowDown
import XCTest

class EvaluationSessionTests: XCTestCase {
    var session: EvaluationSession!

    private func decodeVerifier(_ json: String) throws -> EvaluationManifest.Suite.Case.Verifier {
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvaluationManifest.Suite.Case.Verifier.self, from: data)
    }

    private func roundTrip(
        _ verifier: EvaluationManifest.Suite.Case.Verifier
    ) throws -> EvaluationManifest.Suite.Case.Verifier {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(verifier)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(EvaluationManifest.Suite.Case.Verifier.self, from: data)
    }

    override func setUp() {
        super.setUp()
        // Provide dummy options if needed.
        let emptyManifest = EvaluationManifest(title: "Test", description: "", suites: [])
        let options = EvaluationOptions(modelIdentifier: "test-model", manifesets: [emptyManifest])
        session = EvaluationSession(options: options)
    }

    func testVerifyMatch() {
        let response = ChatResponse(reasoning: "", text: "Hello World", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.match(pattern: "Hello World")]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifyMatchFail() {
        let response = ChatResponse(reasoning: "", text: "Hello World", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.match(pattern: "Hello")]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.fail)
    }

    func testVerifyContains() {
        let response = ChatResponse(reasoning: "", text: "The quick brown fox", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.contains(pattern: "brown")]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifyContainsCaseInsensitive() {
        let response = ChatResponse(reasoning: "", text: "The quick brown fox", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.containsCaseInsensitive(pattern: "BROWN")]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifyRegex() {
        let response = ChatResponse(reasoning: "", text: "Order ID: 12345", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.matchRegularExpression(pattern: #"Order ID: \d+"#)]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifyMatchCaseInsensitive() {
        let response = ChatResponse(reasoning: "", text: "Hello World", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.matchCaseInsensitive(pattern: "hello world")]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifyOpen() {
        let response = ChatResponse(reasoning: "", text: "Some creative text", images: [], tools: [])
        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.open]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.awaitingJudging)
    }

    func testVerifyTool() {
        let toolCall = ToolRequest(id: "call_1", name: "calculator", args: #"{"a": 1, "b": 2}"#)
        let response = ChatResponse(reasoning: "", text: "", images: [], tools: [toolCall])

        let verifiers: [EvaluationManifest.Suite.Case.Verifier] = [.tool(parameter: "a", value: 1)]

        let outcome = session.verify(response: response, verifiers: verifiers)
        XCTAssertEqual(outcome, EvaluationManifest.Suite.Case.Result.Outcome.pass)
    }

    func testVerifierEncodeDecodeRoundTrip_AllCases() throws {
        let all: [EvaluationManifest.Suite.Case.Verifier] = [
            .open,
            .match(pattern: "Hello"),
            .matchCaseInsensitive(pattern: "Hello"),
            .matchRegularExpression(pattern: #"Order ID: \d+"#),
            .contains(pattern: "brown"),
            .containsCaseInsensitive(pattern: "BROWN"),
            .tool(parameter: "a", value: 1),
        ]

        for verifier in all {
            XCTAssertEqual(try roundTrip(verifier), verifier)
        }
    }

    func testVerifierDecode_CurrentFormat_AllCases_ObjectPayloads() throws {
        let cases: [(String, EvaluationManifest.Suite.Case.Verifier)] = [
            (#"{"open":{}}"#, .open),
            (#"{"match":{"pattern":"Hello"}}"#, .match(pattern: "Hello")),
            (#"{"matchCaseInsensitive":{"pattern":"Hello"}}"#, .matchCaseInsensitive(pattern: "Hello")),
            (#"{"matchRegularExpression":{"pattern":"\\d+"}}"#, .matchRegularExpression(pattern: #"\d+"#)),
            (#"{"contains":{"pattern":"brown"}}"#, .contains(pattern: "brown")),
            (#"{"containsCaseInsensitive":{"pattern":"BROWN"}}"#, .containsCaseInsensitive(pattern: "BROWN")),
            (#"{"tool":{"parameter":"a","value":1}}"#, .tool(parameter: "a", value: 1)),
        ]

        for (json, expected) in cases {
            XCTAssertEqual(try decodeVerifier(json), expected)
        }
    }

    func testVerifierDecode_CurrentFormat_AllPatternCases_StringPayloads() throws {
        let cases: [(String, EvaluationManifest.Suite.Case.Verifier)] = [
            (#"{"match":"Hello"}"#, .match(pattern: "Hello")),
            (#"{"matchCaseInsensitive":"Hello"}"#, .matchCaseInsensitive(pattern: "Hello")),
            (#"{"matchRegularExpression":"\\d+"}"#, .matchRegularExpression(pattern: #"\d+"#)),
            (#"{"contains":"brown"}"#, .contains(pattern: "brown")),
            (#"{"containsCaseInsensitive":"BROWN"}"#, .containsCaseInsensitive(pattern: "BROWN")),
        ]

        for (json, expected) in cases {
            XCTAssertEqual(try decodeVerifier(json), expected)
        }
    }

    func testVerifierDecode_CurrentFormat_ToolInlineFieldsVariant() throws {
        // Decoder supports an older variant where `tool` is present but parameter/value are inlined.
        let json = #"{"tool":{},"parameter":"a","value":1}"#
        XCTAssertEqual(try decodeVerifier(json), .tool(parameter: "a", value: 1))
    }

    func testVerifierDecode_LegacyPatternOnly_DefaultsToMatch() throws {
        XCTAssertEqual(try decodeVerifier(#"{"pattern":"Hello World"}"#), .match(pattern: "Hello World"))
    }

    func testVerifierDecode_LegacyTypeAndPattern() throws {
        XCTAssertEqual(try decodeVerifier(#"{"type":"contains","pattern":"brown"}"#), .contains(pattern: "brown"))
    }

    func testVerifierDecode_LegacyType_AllCases() throws {
        let cases: [(String, EvaluationManifest.Suite.Case.Verifier)] = [
            (#"{"type":"open"}"#, .open),
            (#"{"type":"match","pattern":"Hello"}"#, .match(pattern: "Hello")),
            (#"{"type":"matchCaseInsensitive","pattern":"Hello"}"#, .matchCaseInsensitive(pattern: "Hello")),
            (#"{"type":"matchRegularExpression","pattern":"\\d+"}"#, .matchRegularExpression(pattern: #"\d+"#)),
            (#"{"type":"contains","pattern":"brown"}"#, .contains(pattern: "brown")),
            (#"{"type":"containsCaseInsensitive","pattern":"BROWN"}"#, .containsCaseInsensitive(pattern: "BROWN")),
            (#"{"type":"tool","parameter":"a","value":1}"#, .tool(parameter: "a", value: 1)),
        ]

        for (json, expected) in cases {
            XCTAssertEqual(try decodeVerifier(json), expected)
        }
    }

    func testVerifierDecode_LegacyPatternFlags_InferCaseInsensitiveAndRegex() throws {
        XCTAssertEqual(
            try decodeVerifier(#"{"pattern":"Hello","caseInsensitive":true}"#),
            .matchCaseInsensitive(pattern: "Hello"),
        )
        XCTAssertEqual(
            try decodeVerifier(#"{"pattern":"\\d+","regex":true}"#),
            .matchRegularExpression(pattern: #"\d+"#),
        )
    }

    func testVerifierDecode_LegacyToolInlineFields() throws {
        XCTAssertEqual(
            try decodeVerifier(#"{"type":"tool","parameter":"a","value":1}"#),
            .tool(parameter: "a", value: 1)
        )
    }

    func testVerifierDecode_LegacyStringOpen() throws {
        XCTAssertEqual(try decodeVerifier(#""open""#), .open)
    }

    func testExcludedSuitesAreNotIncludedInSessionManifests() {
        let caseA = EvaluationManifest.Suite.Case(title: "A", content: [], verifier: [])
        let caseB = EvaluationManifest.Suite.Case(title: "B", content: [], verifier: [])

        let suite1 = EvaluationManifest.Suite(title: "Suite 1", description: "", cases: [caseA])
        let suite2 = EvaluationManifest.Suite(title: "Suite 2", description: "", cases: [caseB])

        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite1, suite2])
        let options = EvaluationOptions(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            excludedSuites: [suite2.id],
            excludedCases: [],
            options: .init(maxConcurrentRequests: 1, shots: 1),
        )

        let newSession = EvaluationSession(options: options)
        XCTAssertEqual(newSession.manifests.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.id, suite1.id)
    }

    func testExcludedCasesAreNotIncludedInSessionManifests() {
        let caseA = EvaluationManifest.Suite.Case(title: "A", content: [], verifier: [])
        let caseB = EvaluationManifest.Suite.Case(title: "B", content: [], verifier: [])

        let suite = EvaluationManifest.Suite(title: "Suite", description: "", cases: [caseA, caseB])
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite])

        let options = EvaluationOptions(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            excludedSuites: [],
            excludedCases: [caseB.id],
            options: .init(maxConcurrentRequests: 1, shots: 1),
        )

        let newSession = EvaluationSession(options: options)
        XCTAssertEqual(newSession.manifests.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.cases.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.cases.first?.id, caseA.id)
    }

    func testExcludingAllCasesRemovesSuiteAndManifest() {
        let caseA = EvaluationManifest.Suite.Case(title: "A", content: [], verifier: [])
        let caseB = EvaluationManifest.Suite.Case(title: "B", content: [], verifier: [])

        let suite = EvaluationManifest.Suite(title: "Suite", description: "", cases: [caseA, caseB])
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite])

        let options = EvaluationOptions(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            excludedSuites: [],
            excludedCases: [caseA.id, caseB.id],
            options: .init(maxConcurrentRequests: 1, shots: 1),
        )

        let newSession = EvaluationSession(options: options)
        XCTAssertTrue(newSession.manifests.isEmpty)
    }

    func testExcludingAllSuitesRemovesManifest() {
        let caseA = EvaluationManifest.Suite.Case(title: "A", content: [], verifier: [])

        let suite = EvaluationManifest.Suite(title: "Suite", description: "", cases: [caseA])
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite])

        let options = EvaluationOptions(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            excludedSuites: [suite.id],
            excludedCases: [],
            options: .init(maxConcurrentRequests: 1, shots: 1),
        )

        let newSession = EvaluationSession(options: options)
        XCTAssertTrue(newSession.manifests.isEmpty)
    }

    func testCombinedExcludedSuitesAndCases() {
        let suite1CaseA = EvaluationManifest.Suite.Case(title: "A", content: [], verifier: [])
        let suite1CaseB = EvaluationManifest.Suite.Case(title: "B", content: [], verifier: [])
        let suite2CaseC = EvaluationManifest.Suite.Case(title: "C", content: [], verifier: [])

        let suite1 = EvaluationManifest.Suite(title: "Suite 1", description: "", cases: [suite1CaseA, suite1CaseB])
        let suite2 = EvaluationManifest.Suite(title: "Suite 2", description: "", cases: [suite2CaseC])
        let manifest = EvaluationManifest(title: "Manifest", description: "", suites: [suite1, suite2])

        let options = EvaluationOptions(
            modelIdentifier: "test-model",
            manifesets: [manifest],
            excludedSuites: [suite2.id],
            excludedCases: [suite1CaseB.id],
            options: .init(maxConcurrentRequests: 1, shots: 1),
        )

        let newSession = EvaluationSession(options: options)
        XCTAssertEqual(newSession.manifests.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.id, suite1.id)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.cases.count, 1)
        XCTAssertEqual(newSession.manifests.first?.suites.first?.cases.first?.id, suite1CaseA.id)
    }
}

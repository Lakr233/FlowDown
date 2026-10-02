//
//  EvaluationToolVerifierTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@testable import FlowDown
import Foundation
import Testing

struct EvaluationToolVerifierTests {
    private let session = EvaluationSession(options: .init(
        modelIdentifier: "test-model",
        manifesets: [EvaluationManifest(title: "Test", description: "", suites: [])],
    ))

    private func outcome(
        args: String,
        parameter: String,
        value: AnyCodingValue,
    ) -> EvaluationManifest.Suite.Case.Result.Outcome {
        session.verify(
            response: ChatResponse(
                reasoning: "",
                text: "",
                images: [],
                tools: [ToolRequest(id: "call_1", name: "open", args: args)],
            ),
            verifiers: [.tool(parameter: parameter, value: value)],
        )
    }

    @Test
    func toolVerifier_stringWithSlashes_passes() {
        #expect(outcome(args: #"{"url":"https://a.com/b"}"#, parameter: "url", value: "https://a.com/b") == .pass)
    }

    @Test
    func toolVerifier_bool_passes() {
        #expect(outcome(args: #"{"on":true}"#, parameter: "on", value: true) == .pass)
        #expect(outcome(args: #"{"on":false}"#, parameter: "on", value: false) == .pass)
    }

    @Test
    func toolVerifier_array_passes() {
        #expect(outcome(args: #"{"tags":["x","y"]}"#, parameter: "tags", value: ["x", "y"]) == .pass)
    }

    @Test
    func toolVerifier_stringWithEmbeddedQuote_passes() {
        #expect(outcome(args: #"{"q":"say \"hi\""}"#, parameter: "q", value: #"say "hi""#) == .pass)
    }

    @Test
    func toolVerifier_intAgainstDouble_passes() {
        #expect(outcome(args: #"{"n":5}"#, parameter: "n", value: .double(5)) == .pass)
        #expect(outcome(args: #"{"n":1.5}"#, parameter: "n", value: .double(1.5)) == .pass)
    }

    @Test
    func toolVerifier_quotedScalar_keepsCrossTypeLeniency() {
        #expect(outcome(args: #"{"n":"5"}"#, parameter: "n", value: 5) == .pass)
        #expect(outcome(args: #"{"n":5}"#, parameter: "n", value: "5") == .pass)
        #expect(outcome(args: #"{"on":"true"}"#, parameter: "on", value: true) == .pass)
    }

    @Test
    func toolVerifier_differentValue_fails() {
        #expect(outcome(args: #"{"url":"https://a.com/c"}"#, parameter: "url", value: "https://a.com/b") == .fail)
        #expect(outcome(args: #"{"on":false}"#, parameter: "on", value: true) == .fail)
        #expect(outcome(args: #"{"tags":["x"]}"#, parameter: "tags", value: ["x", "y"]) == .fail)
        #expect(outcome(args: #"{"n":6}"#, parameter: "n", value: 5) == .fail)
        #expect(outcome(args: #"{"other":5}"#, parameter: "n", value: 5) == .fail)
    }
}

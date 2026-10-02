//
//  InstructionFollowingSuite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation

extension EvaluationManifest.Suite {
    static var instructionFollowing: EvaluationManifest.Suite {
        EvaluationManifest.Suite(
            title: "Instruction Following",
            description: "Tests the model's ability to follow precise instructions with strict output formats.",
            cases: [
                .init(
                    title: "Exact Word Apple",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Reply with exactly the word 'Apple'. Do not add punctuation."
                        ),
                    ],
                    verifier: [.match(pattern: "Apple")],
                ),
                .init(
                    title: "Number 42",
                    content: [
                        .init(type: .request, textRepresentation: "Output the number 42. Only the number."),
                    ],
                    verifier: [.match(pattern: "42")],
                ),
                .init(
                    title: "System Check Phrase",
                    content: [
                        .init(type: .request, textRepresentation: "Repeat the phrase 'System check' exactly."),
                    ],
                    verifier: [.match(pattern: "System check")],
                ),
                .init(
                    title: "Uppercase HELLO",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write the word 'Hello' in all uppercase letters. Output only the word."
                        ),
                    ],
                    verifier: [.match(pattern: "HELLO")],
                ),
                .init(
                    title: "First Letter Banana",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "What is the first letter of the word 'Banana'? Output only the letter."
                        ),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "B")],
                ),
                .init(
                    title: "Reverse abc",
                    content: [
                        .init(type: .request, textRepresentation: "Reverse the string 'abc'. Output only the result."),
                    ],
                    verifier: [.match(pattern: "cba")],
                ),
                .init(
                    title: "Acknowledge Pass",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Say 'pass' if you understand this instruction. Output only that word."
                        ),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "pass")],
                ),
                .init(
                    title: "Current Year 2025",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Output the current year as '2025'. Only the number."
                        ),
                    ],
                    verifier: [.match(pattern: "2025")],
                ),
                .init(
                    title: "Third Word",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Consider the phrase: 'One two three four'. Reply with the third word only."
                        ),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "three")],
                ),
                .init(
                    title: "Uppercase cat",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Convert 'cat' to uppercase. Output only the result."
                        ),
                    ],
                    verifier: [.match(pattern: "CAT")],
                ),
                .init(
                    title: "Larger Number",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Which number is larger: 5 or 10? Reply with the number only."
                        ),
                    ],
                    verifier: [.match(pattern: "10")],
                ),
                .init(
                    title: "Green Sky",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Is the sky usually green? Reply exactly 'Yes' or 'No'."
                        ),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "No")],
                ),
                .init(
                    title: "Bracketed Test",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Format the word 'Test' inside brackets like this: [Start]Test[End]."
                        ),
                    ],
                    verifier: [.match(pattern: "[Start]Test[End]")],
                ),
                .init(
                    title: "JSON Object",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Output a JSON object with key 'key' and value 'value'. Compact format, no whitespace outside strings."
                        ),
                    ],
                    verifier: [.match(pattern: "{\"key\":\"value\"}")],
                ),
                .init(
                    title: "USD Symbol",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Reply with the currency symbol for US Dollar. Only the symbol."
                        ),
                    ],
                    verifier: [.match(pattern: "$")],
                ),
                .init(
                    title: "Alphabet B",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "What letter comes immediately after A in the English alphabet? Reply with the letter only."
                        ),
                    ],
                    verifier: [.match(pattern: "B")],
                ),
                .init(
                    title: "Triple Code",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Write the word 'Code' three times, separated by a single space."
                        ),
                    ],
                    verifier: [.match(pattern: "Code Code Code")],
                ),
                .init(
                    title: "Represent C",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "If 1 represents A, and 2 represents B, what letter does 3 represent? Reply with the letter only."
                        ),
                    ],
                    verifier: [.match(pattern: "C")],
                ),
                .init(
                    title: "Combine Sunday",
                    content: [
                        .init(
                            type: .request,
                            textRepresentation: "Combine the words 'Sun' and 'Day' into one word. Output only the result."
                        ),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "Sunday")],
                ),
                .init(
                    title: "Acknowledge Confirmed",
                    content: [
                        .init(type: .request, textRepresentation: "Reply with 'Confirmed' to acknowledge."),
                    ],
                    verifier: [.matchCaseInsensitive(pattern: "Confirmed")],
                ),
            ],
        )
    }
}

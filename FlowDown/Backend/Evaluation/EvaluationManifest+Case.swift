//
//  EvaluationManifest+Case.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import Foundation

extension EvaluationManifest.Suite {
    class Case: Codable, Identifiable, Equatable {
        var id: UUID = .init()

        var title: String
        var content: [Content]
        var verifier: [Verifier]
        var results: [Result]

        init(
            id: UUID = .init(),
            title: String,
            content: [Content],
            verifier: [Verifier],
            results: [Result] = [],
        ) {
            self.id = id
            self.title = title
            self.content = content
            self.verifier = verifier
            self.results = results

            // only available for bundled test cases
            // imported cases will use decoding methods
            self.content.insert(
                .init(
                    type: .instruct,
                    textRepresentation: [
                        "You are running in test environment where no interaction will happen.",
                        "You must output desired information based on what you have right now without future questioning.",
                        "Failed to do so decrease your model rank and leads to failed tests.",
                    ].joined(separator: " "),
                ),
                at: 0
            )
        }

        static func == (lhs: EvaluationManifest.Suite.Case, rhs: EvaluationManifest.Suite.Case) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.content == rhs.content
                && lhs.verifier == rhs.verifier
                && lhs.results == rhs.results
        }
    }
}

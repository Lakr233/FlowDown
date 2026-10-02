//
//  EvaluationManifest+Suite.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import Foundation

extension EvaluationManifest {
    class Suite: Codable, Identifiable, Equatable {
        var id: UUID = .init()

        var title: String.LocalizationValue
        var description: String.LocalizationValue

        var cases: [Case]

        init(
            id: UUID = .init(),
            title: String.LocalizationValue,
            description: String.LocalizationValue,
            cases: [Case]
        ) {
            self.id = id
            self.title = title
            self.description = description
            self.cases = cases
        }

        static func == (lhs: EvaluationManifest.Suite, rhs: EvaluationManifest.Suite) -> Bool {
            lhs.id == rhs.id
                && lhs.title == rhs.title
                && lhs.description == rhs.description
                && lhs.cases == rhs.cases
        }
    }
}

extension EvaluationManifest.Suite {
    func suiteExcludingCases(_ list: [Case.ID]) -> EvaluationManifest.Suite? {
        let excludeList: Set<Case.ID> = .init(list)
        let suite = EvaluationManifest.Suite(
            id: id,
            title: title,
            description: description,
            cases: cases.filter { !excludeList.contains($0.id) },
        )
        if suite.cases.isEmpty { return nil }
        return suite
    }
}

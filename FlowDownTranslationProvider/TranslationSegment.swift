//
//  TranslationSegment.swift
//  FlowDown
//
//  Created by qaq on 13/12/2025.
//

import Foundation

struct TranslationSegment: Identifiable, Equatable {
    let id: UUID = .init()

    let input: String
    let translated: String
}

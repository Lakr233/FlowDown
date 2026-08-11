//
//  ModelManager+AutoSelect.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import ChatClientKit
import Foundation

extension ModelManager {
    /// Picks a model on the user's behalf when nothing was ever selected.
    /// Cloud models come first with a random pick, then local models, then Apple Intelligence.
    func automaticSelectionCandidate() -> ModelIdentifier? {
        let cloudCandidates = cloudModels.value.filter { !$0.model_identifier.isEmpty }
        if let candidate = cloudCandidates.randomElement() {
            return candidate.id
        }

        let localCandidates = localModels.value.filter { !$0.model_identifier.isEmpty }
        if let candidate = localCandidates.first {
            return candidate.id
        }

        if appleIntelligenceEnabled,
           #available(iOS 26.0, macCatalyst 26.0, *),
           AppleIntelligenceModel.shared.isAvailable
        {
            return AppleIntelligenceModel.shared.modelIdentifier
        }

        return nil
    }
}

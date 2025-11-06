//
//  PollinationsService.swift
//  FlowDown
//
//  Created by AI Assistant on 11/4/25.
//

import Foundation
import Storage

struct PollinationsModel: Codable {
    let name: String
    let tier: String
    let input_modalities: [String]
    let output_modalities: [String]
    let tools: Bool?
    let vision: Bool?
}

class PollinationsService {
    static let shared = PollinationsService()

    private let endpoint = "https://text.pollinations.ai/models"
    private let openaiEndpoint = "https://text.pollinations.ai/openai/v1/chat/completions"

    private init() {}

    func fetchAvailableModels() async throws -> [PollinationsModel] {
        guard let url = URL(string: endpoint) else {
            throw URLError(.badURL)
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200
        else {
            throw URLError(.badServerResponse)
        }

        let models = try JSONDecoder().decode([PollinationsModel].self, from: data)

        let anonymousModel = models.filter { $0.tier == "anonymous" }

        return anonymousModel.filter { model in
            true
                && model.input_modalities.contains("text")
                && model.output_modalities.contains("text")
        }
    }

    func createCloudModel(from pollinationsModel: PollinationsModel) -> CloudModel {
        var capabilities: Set<ModelCapabilities> = []

        if pollinationsModel.tools == true {
            capabilities.insert(.tool)
        }

        if pollinationsModel.vision == true {
            capabilities.insert(.visual)
        }

        let comment = String(
            localized: "This service is provided free of charge by pollinations.ai and includes rate limits. It may be unavailable in certain countries or regions. If you encounter issues, please set up your own model service."
        )

        return CloudModel(
            deviceId: Storage.deviceId,
            objectId: "pollinations_model_\(pollinationsModel.name)",
            model_identifier: pollinationsModel.name,
            endpoint: openaiEndpoint,
            context: .medium_64k,
            capabilities: capabilities,
            comment: comment
        )
    }
}

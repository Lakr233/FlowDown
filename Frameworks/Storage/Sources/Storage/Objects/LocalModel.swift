//
//  LocalModel.swift
//  Storage
//
//  Created by 秋星桥 on 1/27/25.
//

import Foundation

public struct LocalModel: Codable, Equatable, Hashable, Identifiable {
    public var id: String
    public var model_identifier: String
    public var downloaded: Date
    public var size: UInt64
    public var capabilities: Set<ModelCapabilities> = []
    public var context: ModelContextLength
    public var temperature_preference: ModelTemperaturePreference

    public init(
        id: String = UUID().uuidString,
        model_identifier: String,
        downloaded: Date,
        size: UInt64,
        capabilities: Set<ModelCapabilities>,
        context: ModelContextLength = .short_8k,
        temperature_preference: ModelTemperaturePreference = .inherit,
    ) {
        self.id = id
        self.model_identifier = model_identifier
        self.downloaded = downloaded
        self.size = size
        self.capabilities = capabilities
        self.context = context
        self.temperature_preference = temperature_preference
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case model_identifier
        case downloaded
        case size
        case capabilities
        case context
        case temperature_preference
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        model_identifier = try container.decode(String.self, forKey: .model_identifier)
        downloaded = try container.decode(Date.self, forKey: .downloaded)
        size = try container.decode(UInt64.self, forKey: .size)
        capabilities = try container.decodeIfPresent(Set<ModelCapabilities>.self, forKey: .capabilities) ?? []
        context = try container.decodeIfPresent(ModelContextLength.self, forKey: .context) ?? .short_8k
        temperature_preference = try container.decodeIfPresent(
            ModelTemperaturePreference.self,
            forKey: .temperature_preference
        ) ?? .inherit
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(model_identifier, forKey: .model_identifier)
        try container.encode(downloaded, forKey: .downloaded)
        try container.encode(size, forKey: .size)
        if !capabilities.isEmpty {
            try container.encode(capabilities, forKey: .capabilities)
        }
        try container.encode(context, forKey: .context)
        try container.encode(temperature_preference, forKey: .temperature_preference)
    }
}

//
//  CloudModelV1.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

package final class CloudModelV1: Identifiable, Codable, Equatable, Hashable, TableNamed, TableCodable {
    package static let tableName: String = "CloudModel"

    package var id: String = .init()
    package var model_identifier: String = ""
    package var model_list_endpoint: String = ""
    package var creation: Date = .init()
    package var endpoint: String = ""
    package var token: String = ""
    package var headers: [String: String] = [:] // additional headers
    package var capabilities: Set<ModelCapabilities> = []
    package var context: ModelContextLength = .short_8k
    package var temperature_preference: ModelTemperaturePreference = .inherit

    /// can be used when loading model from our server
    /// present to user on the top of the editor page
    package var comment: String = ""

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = CloudModelV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, isUnique: true, defaultTo: "")
            BindColumnConstraint(model_identifier, isNotNull: true, defaultTo: "")
            BindColumnConstraint(model_list_endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(creation, isNotNull: true, defaultTo: Date(timeIntervalSince1970: 0))
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(token, isNotNull: true, defaultTo: "")
            BindColumnConstraint(headers, isNotNull: true, defaultTo: [String: String]())
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: Set<ModelCapabilities>())
            BindColumnConstraint(context, isNotNull: true, defaultTo: ModelContextLength.short_8k)
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(temperature_preference, isNotNull: true, defaultTo: ModelTemperaturePreference.inherit)
        }

        case id
        case model_identifier
        case model_list_endpoint
        case creation
        case endpoint
        case token
        case headers
        case capabilities
        case context
        case comment
        case temperature_preference
    }

    package init(
        id: String = UUID().uuidString,
        model_identifier: String = "",
        model_list_endpoint: String = "$INFERENCE_ENDPOINT$/../../models",
        creation: Date = .init(),
        endpoint: String = "",
        token: String = "",
        headers: [String: String] = [:],
        context _: ModelContextLength = .medium_64k,
        capabilities: Set<ModelCapabilities> = [],
        comment: String = "",
        temperature_preference: ModelTemperaturePreference = .inherit,
    ) {
        self.id = id
        self.model_identifier = model_identifier
        self.model_list_endpoint = model_list_endpoint
        self.creation = creation
        self.endpoint = endpoint
        self.token = token
        self.headers = headers
        self.capabilities = capabilities
        self.comment = comment
        self.temperature_preference = temperature_preference
    }

    package required init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        model_identifier = try container.decodeIfPresent(String.self, forKey: .model_identifier) ?? ""
        model_list_endpoint = try container.decodeIfPresent(String.self, forKey: .model_list_endpoint) ?? ""
        creation = try container.decodeIfPresent(Date.self, forKey: .creation) ?? Date()
        endpoint = try container.decodeIfPresent(String.self, forKey: .endpoint) ?? ""
        token = try container.decodeIfPresent(String.self, forKey: .token) ?? ""
        headers = try container.decodeIfPresent([String: String].self, forKey: .headers) ?? [:]
        capabilities = try container.decodeIfPresent(Set<ModelCapabilities>.self, forKey: .capabilities) ?? []
        context = try container.decodeIfPresent(ModelContextLength.self, forKey: .context) ?? .short_8k
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        temperature_preference = try container.decodeIfPresent(
            ModelTemperaturePreference.self,
            forKey: .temperature_preference
        ) ?? .inherit
    }

    package static func == (lhs: CloudModelV1, rhs: CloudModelV1) -> Bool {
        lhs.hashValue == rhs.hashValue
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(model_identifier)
        hasher.combine(model_list_endpoint)
        hasher.combine(creation)
        hasher.combine(endpoint)
        hasher.combine(token)
        hasher.combine(headers)
        hasher.combine(capabilities)
        hasher.combine(context)
        hasher.combine(comment)
        hasher.combine(temperature_preference)
    }
}

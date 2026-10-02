//
//  ModelContextServerV1.swift
//  Storage
//
//  Created by LiBr on 6/29/25.
//

import Foundation
import WCDBSwift

package final class ModelContextServerV1: Identifiable, Codable, TableNamed, TableCodable {
    package static let tableName: String = "ModelContextServer"

    package var id: String = UUID().uuidString
    package var name: String = ""
    package var comment: String = ""
    package var type: ModelContextServer.ServerType = .http
    package var endpoint: String = ""
    package var header: String = ""
    package var timeout: Int = 60
    package var isEnabled: Bool = true
    package var toolsEnabled: ModelContextServer.EnableCodable = .init()
    package var resourcesEnabled: ModelContextServer.EnableCodable = .init()
    package var templateEnabled: ModelContextServer.EnableCodable = .init()
    package var lastConnected: Date?
    package var connectionStatus: ModelContextServer.ConnectionStatus = .disconnected
    package var capabilities: StringArrayCodable = .init([])

    package enum CodingKeys: String, CodingTableKey {
        package typealias Root = ModelContextServerV1
        package static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(id, isPrimary: true, defaultTo: UUID().uuidString)
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(comment, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: ModelContextServer.ServerType.http.rawValue)
            BindColumnConstraint(endpoint, isNotNull: true, defaultTo: "")
            BindColumnConstraint(header, isNotNull: true, defaultTo: "")
            BindColumnConstraint(timeout, isNotNull: true, defaultTo: 60)
            BindColumnConstraint(isEnabled, isNotNull: true, defaultTo: true)
            BindColumnConstraint(toolsEnabled, isNotNull: true, defaultTo: ModelContextServer.EnableCodable())
            BindColumnConstraint(resourcesEnabled, isNotNull: true, defaultTo: ModelContextServer.EnableCodable())
            BindColumnConstraint(templateEnabled, isNotNull: true, defaultTo: ModelContextServer.EnableCodable())
            BindColumnConstraint(lastConnected, isNotNull: false)
            BindColumnConstraint(
                connectionStatus,
                isNotNull: true,
                defaultTo: ModelContextServer.ConnectionStatus.disconnected.rawValue
            )
            BindColumnConstraint(capabilities, isNotNull: true, defaultTo: StringArrayCodable([]))
        }

        case id
        case name
        case comment
        case type
        case endpoint
        case header
        case timeout
        case isEnabled
        case toolsEnabled
        case templateEnabled
        case resourcesEnabled
        case lastConnected
        case connectionStatus
        case capabilities
    }

    package init(
        id: String = UUID().uuidString,
        name: String = "",
        comment: String = "",
        type: ModelContextServer.ServerType = .http,
        endpoint: String = "",
        header: String = "",
        timeout: Int = 60,
        isEnabled: Bool = true,
        toolsEnabled: ModelContextServer.EnableCodable = .init(),
        resourcesEnabled: ModelContextServer.EnableCodable = .init(),
        templateEnabled: ModelContextServer.EnableCodable = .init(),
        lastConnected: Date? = nil,
        connectionStatus: ModelContextServer.ConnectionStatus = .disconnected,
        capabilities: StringArrayCodable = StringArrayCodable([]),
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.type = type
        self.endpoint = endpoint
        self.header = header
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.toolsEnabled = toolsEnabled
        self.resourcesEnabled = resourcesEnabled
        self.templateEnabled = templateEnabled
        self.lastConnected = lastConnected
        self.connectionStatus = connectionStatus
        self.capabilities = capabilities
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

extension ModelContextServerV1: Equatable {
    package static func == (lhs: ModelContextServerV1, rhs: ModelContextServerV1) -> Bool {
        lhs.id == rhs.id
    }
}

extension ModelContextServerV1: Hashable {}

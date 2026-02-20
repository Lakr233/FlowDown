//
//  Message.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import MarkdownParser
import WCDBSwift

public final class Message: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "Message"

    public var id: String {
        objectId
    }

    public var combinationID: String {
        "\(Int(creation.timeIntervalSince1970 * 1000.0))-\(objectId)"
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = ""
    public package(set) var conversationId: Conversation.ID = .init()
    public package(set) var creation: Date = .now
    public package(set) var role: Role = .system
    public package(set) var thinkingDuration: TimeInterval = 0
    public package(set) var reasoningContent: String = ""
    public package(set) var isThinkingFold: Bool = false
    public package(set) var document: String = ""
    public package(set) var documentNodes: [MarkdownBlockNode] = []
    public package(set) var webSearchStatus: WebSearchStatus = .init()
    public package(set) var toolStatus: ToolStatus = .init()

    public package(set) var removed: Bool = false
    public package(set) var modified: Date = .now

    public package(set) var metadata: Data?

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Message
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(conversationId, isNotNull: true)

            BindColumnConstraint(role, isNotNull: true, defaultTo: Role.system.rawValue)
            BindColumnConstraint(thinkingDuration, isNotNull: true, defaultTo: 0)
            BindColumnConstraint(reasoningContent, isNotNull: true, defaultTo: "")
            BindColumnConstraint(isThinkingFold, isNotNull: true, defaultTo: false)
            BindColumnConstraint(document, isNotNull: true, defaultTo: "")
            BindColumnConstraint(documentNodes, isNotNull: true, defaultTo: [MarkdownBlockNode]())
            BindColumnConstraint(webSearchStatus, isNotNull: true, defaultTo: WebSearchStatus())
            BindColumnConstraint(toolStatus, isNotNull: true, defaultTo: ToolStatus())
            BindColumnConstraint(metadata, isNotNull: false)

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
            BindIndex(conversationId, namedWith: "_conversationIdIndex")
        }

        case objectId
        case deviceId
        case conversationId
        case creation
        case role
        case thinkingDuration
        case reasoningContent
        case isThinkingFold
        case document
        case documentNodes
        case webSearchStatus
        case toolStatus

        case removed
        case modified
        case metadata
    }

    public init(deviceId: String) {
        self.deviceId = deviceId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension Message: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Message, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<Message, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (Message) -> Void) {
        block(self)
        markModified()
    }
}

public extension Message.Role {
    /// role of supplement kind, requires a message to live
    var isSupplementKind: Bool {
        switch self {
        case .userAttachmentHint:
            true
        case .hint:
            true
        case .webSearch:
            true
        case .user:
            false
        case .assistant:
            false
        case .system:
            false
        case .toolHint:
            false // 不然会被删掉了 这个是包含信息的
        }
    }
}

public extension Message {
    enum Role: String, Codable, ColumnCodable {
        public init?(with value: WCDBSwift.Value) {
            self.init(rawValue: value.stringValue)
        }

        public func archivedValue() -> WCDBSwift.Value {
            .init(rawValue)
        }

        public static var columnType: WCDBSwift.ColumnType {
            .text
        }

        case user
        /// Attachments are now maintained in a dedicated table.
        /// The use of this role to denote attachments has been discontinued.
        /// This value is considered *deprecated*.
        case userAttachmentHint
        case assistant
        case system
        case hint
        case webSearch
        case toolHint
    }
}

public extension Message {
    struct WebSearchStatus: Codable, ColumnCodable, Hashable {
        public var id: UUID = .init()

        public var queries: [String] = []
        public var currentQuery: Int = 0
        public var currentQueryBeginDate: Date = .init(timeIntervalSince1970: 0)
        public var currentSource: Int = 0
        public var numberOfSource: Int = 0
        public var numberOfWebsites: Int = 0
        public var numberOfResults: Int = 0
        public var proccessProgress: Double = 0

        public struct SearchResult: Codable, Hashable {
            public var title: String
            public var url: URL

            public init(title: String, url: URL) {
                self.title = title
                self.url = url
            }
        }

        public var searchResults: [SearchResult] = []

        public init() {}

        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(
                Message.WebSearchStatus.self,
                from: data,
            ) else {
                return nil
            }
            self = object
        }

        public func archivedValue() -> WCDBSwift.Value {
            do {
                let data = try JSONEncoder().encode(self)
                return .init(data)
            } catch {
                assertionFailure("failed to encode Message.WebSearchStatus: \(error)")
                return .init(Data())
            }
        }

        public static var columnType: WCDBSwift.ColumnType {
            .BLOB
        }
    }
}

public extension Message {
    struct ToolStatus: Identifiable, Codable, ColumnCodable, Hashable, Equatable {
        public var id: UUID = .init()
        public var name: String = .init()
        public var state: Int = 0
        public var message: String = ""

        public init?(with value: WCDBSwift.Value) {
            let data = value.dataValue
            guard let object = try? JSONDecoder().decode(
                Message.ToolStatus.self,
                from: data,
            ) else {
                return nil
            }
            self = object
        }

        public func archivedValue() -> WCDBSwift.Value {
            do {
                let data = try JSONEncoder().encode(self)
                return .init(data)
            } catch {
                assertionFailure("failed to encode Message.ToolStatus: \(error)")
                return .init(Data())
            }
        }

        public static var columnType: WCDBSwift.ColumnType {
            .BLOB
        }

        public init(name: String = .init(), state: Int = 0, message: String = .init()) {
            self.name = name
            self.state = state
            self.message = message
        }
    }
}

extension Message: Equatable {
    public static func == (lhs: Message, rhs: Message) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.conversationId == rhs.conversationId &&
            lhs.creation == rhs.creation &&
            lhs.role == rhs.role &&
            lhs.thinkingDuration == rhs.thinkingDuration &&
            lhs.reasoningContent == rhs.reasoningContent &&
            lhs.isThinkingFold == rhs.isThinkingFold &&
            lhs.document == rhs.document &&
            lhs.webSearchStatus == rhs.webSearchStatus &&
            lhs.removed == rhs.removed &&
            lhs.modified == rhs.modified
    }
}

extension Message: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(conversationId)
        hasher.combine(creation)
        hasher.combine(role)
        hasher.combine(thinkingDuration)
        hasher.combine(reasoningContent)
        hasher.combine(isThinkingFold)
        hasher.combine(document)
        hasher.combine(webSearchStatus)

        hasher.combine(removed)
        hasher.combine(modified)
    }
}

extension MarkdownBlockNode: @retroactive ColumnCodable {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        let object = try? Self.decoder.decode(
            MarkdownBlockNode.self,
            from: data,
        )
        if let object {
            self = object
        } else {
            return nil
        }
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = try? Self.encoder.encode(self)
        return .init(data ?? .init())
    }

    public static var columnType: ColumnType {
        .BLOB
    }
}

extension Message.WebSearchStatus.SearchResult: ColumnCodable {
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()
    public init?(with value: WCDBSwift.Value) {
        let data = value.dataValue
        let object = try? Self.decoder.decode(
            Message.WebSearchStatus.SearchResult.self,
            from: data,
        )
        if let object {
            self = object
        } else {
            return nil
        }
    }

    public func archivedValue() -> WCDBSwift.Value {
        let data = try? Self.encoder.encode(self)
        return .init(data ?? .init())
    }

    public static var columnType: ColumnType {
        .BLOB
    }
}

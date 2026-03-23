//
//  ConversationSummary.swift
//  Storage
//
//  Created by Alan Ye on 3/23/26.
//

import Foundation
import WCDBSwift

public final class ConversationSummary: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "ConversationSummary"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = ""
    public package(set) var conversationId: String = ""
    public package(set) var summary: String = ""
    public package(set) var topics: String = ""
    public package(set) var messageCount: Int = 0
    public package(set) var creation: Date = .now
    public package(set) var modified: Date = .now
    public package(set) var removed: Bool = false

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ConversationSummary
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(conversationId, isNotNull: true, isUnique: true)
            BindColumnConstraint(summary, isNotNull: true, defaultTo: "")
            BindColumnConstraint(topics, isNotNull: true, defaultTo: "")
            BindColumnConstraint(messageCount, isNotNull: true, defaultTo: 0)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
            BindIndex(conversationId, namedWith: "_conversationIdIndex")
        }

        case objectId
        case deviceId
        case conversationId
        case summary
        case topics
        case messageCount
        case creation
        case modified
        case removed
    }

    public init(deviceId: String, conversationId: String) {
        self.deviceId = deviceId
        self.conversationId = conversationId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension ConversationSummary: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ConversationSummary, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<ConversationSummary, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (ConversationSummary) -> Void) {
        block(self)
        markModified()
    }
}

extension ConversationSummary: Equatable {
    public static func == (lhs: ConversationSummary, rhs: ConversationSummary) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.conversationId == rhs.conversationId &&
            lhs.summary == rhs.summary &&
            lhs.topics == rhs.topics &&
            lhs.messageCount == rhs.messageCount &&
            lhs.creation == rhs.creation &&
            lhs.modified == rhs.modified &&
            lhs.removed == rhs.removed
    }
}

extension ConversationSummary: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(conversationId)
        hasher.combine(summary)
        hasher.combine(topics)
        hasher.combine(messageCount)
        hasher.combine(creation)
        hasher.combine(modified)
        hasher.combine(removed)
    }
}

//
//  Memory.swift
//  Storage
//
//  Created by Alan Ye on 8/14/25.
//

import Foundation
import WCDBSwift

public final class Memory: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "Memory"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = ""
    public package(set) var content: String = ""
    public package(set) var creation: Date = .now
    public package(set) var conversationId: String? = nil

    public package(set) var removed: Bool = false
    public package(set) var modified: Date = .now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Memory
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(content, isNotNull: true, defaultTo: "")
            BindColumnConstraint(conversationId, isNotNull: false, defaultTo: nil)

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
            BindIndex(conversationId, namedWith: "_conversationIdIndex")
        }

        case objectId
        case deviceId
        case content
        case creation
        case conversationId

        case removed
        case modified
    }

    public init(deviceId: String, content: String, conversationId: String? = nil) {
        self.deviceId = deviceId
        self.content = content
        self.conversationId = conversationId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension Memory: Updatable {
    @discardableResult
    public func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Memory, Value>,
        to newValue: Value
    ) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<Memory, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }
}

extension Memory: Equatable {
    public static func == (lhs: Memory, rhs: Memory) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.content == rhs.content &&
            lhs.creation == rhs.creation &&
            lhs.modified == rhs.modified &&
            lhs.conversationId == rhs.conversationId &&
            lhs.removed == rhs.removed
    }
}

extension Memory: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(content)
        hasher.combine(creation)
        hasher.combine(modified)
        hasher.combine(conversationId)
        hasher.combine(removed)
    }
}

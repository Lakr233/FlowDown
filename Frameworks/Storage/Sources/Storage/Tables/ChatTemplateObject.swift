//
//  ChatTemplateObject.swift
//  Storage
//
//  Created by GPT-5 Codex on 2025/11/05.
//

import Foundation
import WCDBSwift

public final class ChatTemplateObject: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "ChatTemplate"

    public var id: String { objectId }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = ""

    public package(set) var name: String = ""
    public package(set) var avatar: Data = .init()
    public package(set) var prompt: String = ""
    public package(set) var inheritApplicationPrompt: Bool = true
    public package(set) var sortIndex: Int = 0

    public package(set) var removed: Bool = false
    public package(set) var creation: Date = .now
    public package(set) var modified: Date = .now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ChatTemplateObject
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(avatar, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(prompt, isNotNull: true, defaultTo: "")
            BindColumnConstraint(inheritApplicationPrompt, isNotNull: true, defaultTo: true)
            BindColumnConstraint(sortIndex, isNotNull: true, defaultTo: 0)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: true, defaultTo: false)

            BindIndex(sortIndex, namedWith: "_sortIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
        }

        case objectId
        case deviceId
        case name
        case avatar
        case prompt
        case inheritApplicationPrompt
        case sortIndex
        case creation
        case modified
        case removed
    }

    public init(deviceId: String) {
        self.deviceId = deviceId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension ChatTemplateObject: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ChatTemplateObject, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<ChatTemplateObject, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (ChatTemplateObject) -> Void) {
        block(self)
        markModified()
    }
}

extension ChatTemplateObject: Equatable {
    public static func == (lhs: ChatTemplateObject, rhs: ChatTemplateObject) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.name == rhs.name &&
            lhs.avatar == rhs.avatar &&
            lhs.prompt == rhs.prompt &&
            lhs.inheritApplicationPrompt == rhs.inheritApplicationPrompt &&
            lhs.sortIndex == rhs.sortIndex &&
            lhs.removed == rhs.removed &&
            lhs.creation == rhs.creation &&
            lhs.modified == rhs.modified
    }
}

extension ChatTemplateObject: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(name)
        hasher.combine(avatar)
        hasher.combine(prompt)
        hasher.combine(inheritApplicationPrompt)
        hasher.combine(sortIndex)
        hasher.combine(removed)
        hasher.combine(creation)
        hasher.combine(modified)
    }
}

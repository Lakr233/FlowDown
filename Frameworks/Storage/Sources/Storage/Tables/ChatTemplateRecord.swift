//
//  ChatTemplateRecord.swift
//  Storage
//
//  Created by Assistant on 2025/12/07.
//

import Foundation
import WCDBSwift

public final class ChatTemplateRecord: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public typealias ID = String

    public static let tableName: String = "ChatTemplate"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = Storage.deviceId
    public package(set) var name: String = ""
    public package(set) var avatar: Data = .init()
    public package(set) var prompt: String = ""
    public package(set) var inheritApplicationPrompt: Bool = true
    public package(set) var sortIndex: Double = 0
    public package(set) var creation: Date = .now
    public package(set) var modified: Date = .now
    public package(set) var removed: Bool = false

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ChatTemplateRecord
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(avatar, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(prompt, isNotNull: true, defaultTo: "")
            BindColumnConstraint(inheritApplicationPrompt, isNotNull: true, defaultTo: true)
            BindColumnConstraint(sortIndex, isNotNull: true, defaultTo: 0)

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
            BindIndex(sortIndex, namedWith: "_sortIndex")
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

    public init(
        deviceId: String,
        objectId: String = UUID().uuidString,
        name: String = "",
        avatar: Data = .init(),
        prompt: String = "",
        inheritApplicationPrompt: Bool = true,
        sortIndex: Double = 0,
        creation: Date = .now,
    ) {
        self.deviceId = deviceId
        self.objectId = objectId
        self.name = name
        self.avatar = avatar
        self.prompt = prompt
        self.inheritApplicationPrompt = inheritApplicationPrompt
        self.sortIndex = sortIndex
        self.creation = creation
        modified = creation
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension ChatTemplateRecord: Updatable {
    @discardableResult
    public func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<ChatTemplateRecord, Value>,
        to newValue: Value
    ) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<ChatTemplateRecord, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }
}

extension ChatTemplateRecord: Equatable {
    public static func == (lhs: ChatTemplateRecord, rhs: ChatTemplateRecord) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.name == rhs.name &&
            lhs.avatar == rhs.avatar &&
            lhs.prompt == rhs.prompt &&
            lhs.inheritApplicationPrompt == rhs.inheritApplicationPrompt &&
            lhs.sortIndex == rhs.sortIndex &&
            lhs.creation == rhs.creation &&
            lhs.modified == rhs.modified &&
            lhs.removed == rhs.removed
    }
}

extension ChatTemplateRecord: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(name)
        hasher.combine(avatar)
        hasher.combine(prompt)
        hasher.combine(inheritApplicationPrompt)
        hasher.combine(sortIndex)
        hasher.combine(creation)
        hasher.combine(modified)
        hasher.combine(removed)
    }
}

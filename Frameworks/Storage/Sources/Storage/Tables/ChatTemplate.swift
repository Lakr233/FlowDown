//
//  ChatTemplate.swift
//  Storage
//
//  Created by GPT-5 Codex on 2025/11/05.
//

import Foundation
import WCDBSwift

public final class ChatTemplateRecord: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "ChatTemplate"

    public var id: String {
        objectId
    }

    public var objectId: String = UUID().uuidString
    public var deviceId: String = ""
    public var name: String = ""
    public var prompt: String = ""
    public var inheritApplicationPrompt: Bool = true
    public var avatarData: Data = .init()
    public var sortIndex: Int = 0
    public var creation: Date = .now
    public var modified: Date = .now
    public var removed: Bool = false

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = ChatTemplateRecord

        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isPrimary: true, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(prompt, isNotNull: true, defaultTo: "")
            BindColumnConstraint(inheritApplicationPrompt, isNotNull: true, defaultTo: true)
            BindColumnConstraint(avatarData, isNotNull: true, defaultTo: Data())
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
        case prompt
        case inheritApplicationPrompt
        case avatarData
        case sortIndex
        case creation
        case modified
        case removed
    }

    public init(
        objectId: String,
        deviceId: String,
        name: String,
        prompt: String,
        inheritApplicationPrompt: Bool,
        avatarData: Data,
        sortIndex: Int,
        creation: Date = .now,
        modified: Date? = nil,
        removed: Bool = false
    ) {
        self.objectId = objectId
        self.deviceId = deviceId
        self.name = name
        self.prompt = prompt
        self.inheritApplicationPrompt = inheritApplicationPrompt
        self.avatarData = avatarData
        self.sortIndex = sortIndex
        self.creation = creation
        self.modified = modified ?? creation
        self.removed = removed
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension ChatTemplateRecord: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<ChatTemplateRecord, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<ChatTemplateRecord, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (ChatTemplateRecord) -> Void) {
        block(self)
        markModified()
    }
}

extension ChatTemplateRecord: Equatable {
    public static func == (lhs: ChatTemplateRecord, rhs: ChatTemplateRecord) -> Bool {
        lhs.objectId == rhs.objectId
            && lhs.deviceId == rhs.deviceId
            && lhs.name == rhs.name
            && lhs.prompt == rhs.prompt
            && lhs.inheritApplicationPrompt == rhs.inheritApplicationPrompt
            && lhs.avatarData == rhs.avatarData
            && lhs.sortIndex == rhs.sortIndex
            && lhs.creation == rhs.creation
            && lhs.modified == rhs.modified
            && lhs.removed == rhs.removed
    }
}

extension ChatTemplateRecord: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(name)
        hasher.combine(prompt)
        hasher.combine(inheritApplicationPrompt)
        hasher.combine(avatarData)
        hasher.combine(sortIndex)
        hasher.combine(creation)
        hasher.combine(modified)
        hasher.combine(removed)
    }
}

extension ChatTemplateRecord: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(
        objectId: ChatTemplateRecord.Properties.objectId.asProperty(),
        creation: ChatTemplateRecord.Properties.creation.asProperty(),
        modified: ChatTemplateRecord.Properties.modified.asProperty(),
        removed: ChatTemplateRecord.Properties.removed.asProperty()
    )

    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

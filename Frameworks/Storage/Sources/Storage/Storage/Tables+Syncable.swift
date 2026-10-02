//
//  Tables+Syncable.swift
//  Storage
//

import Foundation
import WCDBSwift

extension CloudModel: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: CloudModel.Properties.objectId.asProperty(), creation: CloudModel.Properties.creation.asProperty(), modified: CloudModel.Properties.modified.asProperty(), removed: CloudModel.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension ModelContextServer: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: ModelContextServer.Properties.objectId.asProperty(), creation: ModelContextServer.Properties.creation.asProperty(), modified: ModelContextServer.Properties.modified.asProperty(), removed: ModelContextServer.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Memory: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Memory.Properties.objectId.asProperty(), creation: Memory.Properties.creation.asProperty(), modified: Memory.Properties.modified.asProperty(), removed: Memory.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Conversation: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Conversation.Properties.objectId.asProperty(), creation: Conversation.Properties.creation.asProperty(), modified: Conversation.Properties.modified.asProperty(), removed: Conversation.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Message: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Message.Properties.objectId.asProperty(), creation: Message.Properties.creation.asProperty(), modified: Message.Properties.modified.asProperty(), removed: Message.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension Attachment: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: Attachment.Properties.objectId.asProperty(), creation: Attachment.Properties.creation.asProperty(), modified: Attachment.Properties.modified.asProperty(), removed: Attachment.Properties.removed.asProperty())
    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension ChatTemplateRecord: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: ChatTemplateRecord.Properties.objectId.asProperty(), creation: ChatTemplateRecord.Properties.creation.asProperty(), modified: ChatTemplateRecord.Properties.modified.asProperty(), removed: ChatTemplateRecord.Properties.removed.asProperty())

    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

extension ConversationSummary: Syncable, SyncQueryable {
    package static let SyncQuery: SyncQueryProperties = .init(objectId: ConversationSummary.Properties.objectId.asProperty(), creation: ConversationSummary.Properties.creation.asProperty(), modified: ConversationSummary.Properties.modified.asProperty(), removed: ConversationSummary.Properties.removed.asProperty())

    package func encodePayload() throws -> Data {
        try Storage.encodePayloadSyncable(self)
    }

    package static func decodePayload(_ data: Data) throws -> Self {
        try Storage.decodePayloadSyncable(Self.self, data)
    }
}

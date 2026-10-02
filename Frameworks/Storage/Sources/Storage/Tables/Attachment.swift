//
//  Attachment.swift
//  Objects
//
//  Created by 秋星桥 on 1/23/25.
//

import Foundation
import WCDBSwift

public final class Attachment: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "Attachment"

    public var id: String {
        objectId
    }

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = Storage.deviceId
    public package(set) var messageId: String = .init()
    public package(set) var data: Data = .init()
    public package(set) var previewImageData: Data = .init()
    public package(set) var imageRepresentation: Data = .init()
    public package(set) var representedDocument: String = ""
    public package(set) var type: String = ""
    public package(set) var name: String = ""
    public package(set) var storageSuffix: String = ""

    public package(set) var removed: Bool = false
    public package(set) var creation: Date = .now
    public var modified: Date = .now

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Attachment
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(messageId, isNotNull: true, defaultTo: "")

            BindColumnConstraint(data, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(previewImageData, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(representedDocument, isNotNull: true, defaultTo: "")
            BindColumnConstraint(type, isNotNull: true, defaultTo: "")
            BindColumnConstraint(name, isNotNull: true, defaultTo: "")
            BindColumnConstraint(storageSuffix, isNotNull: true, defaultTo: "")
            BindColumnConstraint(imageRepresentation, isNotNull: true, defaultTo: Data())

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
            BindIndex(messageId, namedWith: "_messageIdIndex")
        }

        case objectId
        case deviceId
        case messageId
        case data
        case previewImageData
        case imageRepresentation
        case representedDocument
        case type
        case name
        case storageSuffix

        case removed
        case creation
        case modified
    }

    public init(deviceId: String) {
        self.deviceId = deviceId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension Attachment: Updatable {
    @discardableResult
    public func update<Value: Equatable>(
        _ keyPath: ReferenceWritableKeyPath<Attachment, Value>,
        to newValue: Value
    ) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<Attachment, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }
}

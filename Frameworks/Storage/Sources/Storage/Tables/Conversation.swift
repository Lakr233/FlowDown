// The Swift Programming Language
// https://docs.swift.org/swift-book
import Foundation
import WCDBSwift

public final class Conversation: Identifiable, Codable, TableNamed, DeviceOwned, TableCodable {
    public static let tableName: String = "Conversation"

    public var id: String {
        objectId
    }

    public package(set) var title: String = ""
    public package(set) var creation: Date = .now
    public package(set) var icon: Data = .init()
    public package(set) var isFavorite: Bool = false
    public package(set) var shouldAutoRename: Bool = true
    public package(set) var modelId: String? = nil

    public package(set) var objectId: String = UUID().uuidString
    public package(set) var deviceId: String = ""
    public package(set) var removed: Bool = false
    public package(set) var modified: Date = .init()

    /// 通用扩展容器(plist 编码,key-value 字符串)。模块通过 `ExtensionKey.*` 常量 access。
    /// **永不 rename**。
    public package(set) var ext_data: ExtensionDictionary = .init()

    public enum CodingKeys: String, CodingTableKey {
        public typealias Root = Conversation
        public static let objectRelationalMapping = TableBinding(CodingKeys.self) {
            BindColumnConstraint(objectId, isNotNull: true, isUnique: true)
            BindColumnConstraint(deviceId, isNotNull: true)

            BindColumnConstraint(creation, isNotNull: true)
            BindColumnConstraint(modified, isNotNull: true)
            BindColumnConstraint(removed, isNotNull: false, defaultTo: false)

            BindColumnConstraint(title, isNotNull: true, defaultTo: "")
            BindColumnConstraint(icon, isNotNull: true, defaultTo: Data())
            BindColumnConstraint(isFavorite, isNotNull: true, defaultTo: false)
            BindColumnConstraint(shouldAutoRename, isNotNull: true, defaultTo: true)
            BindColumnConstraint(modelId, isNotNull: false, defaultTo: nil)
            BindColumnConstraint(ext_data, isNotNull: true, defaultTo: ExtensionDictionary())

            BindIndex(creation, namedWith: "_creationIndex")
            BindIndex(modified, namedWith: "_modifiedIndex")
        }

        case objectId
        case deviceId
        case title
        case creation
        case icon
        case isFavorite
        case shouldAutoRename
        case modelId
        case ext_data

        case removed
        case modified
    }

    public init(deviceId: String) {
        self.deviceId = deviceId
    }

    public func markModified(_ date: Date = .now) {
        modified = date
    }
}

extension Conversation: Updatable {
    @discardableResult
    public func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<Conversation, Value>, to newValue: Value) -> Bool {
        let oldValue = self[keyPath: keyPath]
        guard oldValue != newValue else { return false }
        assign(keyPath, to: newValue)
        return true
    }

    public func assign<Value>(_ keyPath: ReferenceWritableKeyPath<Conversation, Value>, to newValue: Value) {
        self[keyPath: keyPath] = newValue
        markModified()
    }

    package func update(_ block: (Conversation) -> Void) {
        block(self)
        markModified()
    }
}

extension Conversation: Equatable {
    public static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.objectId == rhs.objectId &&
            lhs.deviceId == rhs.deviceId &&
            lhs.title == rhs.title &&
            lhs.creation == rhs.creation &&
            lhs.icon == rhs.icon &&
            lhs.isFavorite == rhs.isFavorite &&
            lhs.shouldAutoRename == rhs.shouldAutoRename &&
            lhs.modelId == rhs.modelId &&
            lhs.objectId == rhs.objectId &&
            lhs.removed == rhs.removed &&
            lhs.modified == rhs.modified &&
            lhs.ext_data == rhs.ext_data
    }
}

extension Conversation: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(objectId)
        hasher.combine(deviceId)
        hasher.combine(title)
        hasher.combine(creation)
        hasher.combine(icon)
        hasher.combine(isFavorite)
        hasher.combine(shouldAutoRename)
        hasher.combine(modelId)
        hasher.combine(ext_data)

        hasher.combine(removed)
        hasher.combine(modified)
    }
}

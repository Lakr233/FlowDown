//
//  ExtensionDictionary.swift
//  Storage
//
//  通用 per-record 扩展数据容器。每张表只允许出现一个此字段。
//  字段名固定为 `ext_data`(避开 Swift 关键字 `extension`,
//  并防止 TableBinding KeyPath 反射上的潜在坑)。
//  **永不 rename**:历史上 rename 字段引发过生产事故。
//

import Foundation
import WCDBSwift

public struct ExtensionDictionary: Codable, Equatable, Hashable, Sendable {
    public private(set) var storage: [String: String]

    public init(_ storage: [String: String] = [:]) {
        self.storage = storage
    }

    public subscript(key: String) -> String? {
        get { storage[key] }
        set { storage[key] = newValue }
    }

    public var isEmpty: Bool { storage.isEmpty }
}

extension ExtensionDictionary: ColumnCodable {
    public static let columnType: ColumnType = .text

    public init?(with value: Value) {
        let text = value.stringValue
        guard !text.isEmpty else {
            self = .init()
            return
        }
        let data = Data(text.utf8)
        if let decoded = try? PropertyListDecoder().decode([String: String].self, from: data) {
            self = .init(decoded)
            return
        }
        // Fail-safe:数据损坏 / 老库无数据 → 空 dict。绝不抛。
        self = .init()
    }

    public func archivedValue() -> Value {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .xml // 显式 XML,避免 binary plist 走 TEXT 列丢数据
        guard let data = try? encoder.encode(storage),
              let str = String(data: data, encoding: .utf8)
        else {
            return .init("")
        }
        return .init(str)
    }
}

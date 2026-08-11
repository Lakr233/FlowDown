//
//  ModelCapabilities.swift
//  Storage
//
//  Created by 秋星桥 on 1/27/25.
//

import Foundation
import WCDBSwift

public enum ModelCapabilities: String, Codable, CaseIterable, Equatable {
    case visual
    case auditory
    case tool
    case developerRole
    /// Thinking models that require the original reasoning of every turn to
    /// be preserved: prior reasoning is sent back as `reasoning_content`.
    case preservedThinking
}

public enum ModelContextLength: Int, Codable, CaseIterable, Equatable {
    case short_4k = 4000 // 4k
    case short_8k = 8000 // 8k
    case medium_16k = 16000 // 16k
    case medium_32k = 32000 // 32k
    case medium_64k = 64000 // 64k
    case long_100k = 100_000 // 100k
    case long_200k = 200_000 // 200k
    case huge_1m = 1_000_000 // 1m
    case infinity = 2_147_483_647
}

public enum ModelTemperaturePreference: String, CaseIterable, Equatable {
    case inherit
    case custom
}

extension ModelTemperaturePreference: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = (try? container.decode(String.self)) ?? ""
        if let value = ModelTemperaturePreference(rawValue: rawValue) {
            self = value
        } else {
            self = .inherit
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

extension ModelTemperaturePreference: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self = ModelTemperaturePreference(rawValue: text) ?? .inherit
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

extension ModelCapabilities: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        let text = value.stringValue
        self.init(rawValue: text)
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .text
    }
}

extension ModelContextLength: ColumnCodable {
    public init?(with value: WCDBSwift.Value) {
        self.init(rawValue: value.intValue)
    }

    public func archivedValue() -> WCDBSwift.Value {
        .init(rawValue)
    }

    public static var columnType: ColumnType {
        .integer64
    }
}

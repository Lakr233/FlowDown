//
//  Created by ktiays on 2025/2/25.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import Foundation

public enum JSONValue: Sendable, Codable {
    case null(NSNull)
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case let .bool(bool):
            try container.encode(bool)
        case let .int(int):
            try container.encode(int)
        case let .double(double):
            try container.encode(double)
        case let .string(string):
            try container.encode(string)
        case let .array(array):
            try container.encode(array)
        case let .object(object):
            try container.encode(object)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null(NSNull())
        } else if let bool = try? container.decode(Bool.self) {
            self = .bool(bool)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let array = try? container.decode([JSONValue].self) {
            self = .array(array)
        } else if let object = try? container.decode([String: JSONValue].self) {
            self = .object(object)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unexpected JSON value"
            )
        }
    }
}

public extension [String: JSONValue] {
    var untypedDictionary: [String: Any] {
        convertToUntypedDictionary(self)
    }
}

private func convertToUntyped(_ input: JSONValue) -> Any {
    switch input {
    case .null:
        NSNull()
    case let .bool(bool):
        bool
    case let .int(int):
        int
    case let .double(double):
        double
    case let .string(string):
        string
    case let .array(array):
        array.map { convertToUntyped($0) }
    case let .object(dictionary):
        convertToUntypedDictionary(dictionary)
    }
}

private func convertToUntypedDictionary(
    _ input: [String: JSONValue]
) -> [String: Any] {
    input.mapValues { v in
        switch v {
        case .null:
            NSNull()
        case let .bool(bool):
            bool
        case let .int(int):
            int
        case let .double(double):
            double
        case let .string(string):
            string
        case let .array(array):
            array.map { convertToUntyped($0) }
        case let .object(dictionary):
            convertToUntypedDictionary(dictionary)
        }
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral _: ()) {
        self = .null(NSNull())
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: BooleanLiteralType) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: IntegerLiteralType) {
        self = .int(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: FloatLiteralType) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: StringLiteralType) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

public extension JSONValue {
    /// Extract the underlying value from JSONValue enum
    var value: Any {
        switch self {
        case let .null(null):
            null
        case let .bool(bool):
            bool
        case let .int(int):
            int
        case let .double(double):
            double
        case let .string(string):
            string
        case let .array(array):
            array.map(\.value)
        case let .object(object):
            object.mapValues { $0.value }
        }
    }

    /// Convenience initializer to create JSONValue from Any
    init(_ value: Any) {
        switch value {
        case let null as NSNull:
            self = .null(null)
        case let bool as Bool:
            self = .bool(bool)
        case let int as Int:
            self = .int(int)
        case let double as Double:
            self = .double(double)
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = .array(array.map { JSONValue($0) })
        case let dict as [String: Any]:
            self = .object(dict.mapValues { JSONValue($0) })
        default:
            // Fallback to string representation for unknown types
            self = .string(String(describing: value))
        }
    }
}

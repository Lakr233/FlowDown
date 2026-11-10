//
//  ModelToolArgumentOrder.swift
//  FlowDown
//

import Foundation

/// The order the approval card lists a call's arguments in. Decoding the
/// call's JSON loses the order of its keys, so they are read off the text
/// the model sent.
enum ModelToolArgumentOrder {
    /// The tool's schema order first, then any other key in the order the
    /// model sent it.
    static func order(schema: [String], arguments json: String) -> [String] {
        var seen = Set(schema)
        return schema + keys(in: json).filter { seen.insert($0).inserted }
    }

    /// The keys of the JSON object `json`, in the order they appear, each
    /// once; empty when `json` is not an object.
    static func keys(in json: String) -> [String] {
        var scanner = Scanner(Array(json.utf8))
        guard scanner.take(UInt8(ascii: "{")) else { return [] }
        var keys: [String] = []
        if scanner.take(UInt8(ascii: "}")) { return [] }
        repeat {
            guard let key = scanner.string(), scanner.take(UInt8(ascii: ":")), scanner.skipValue() else { return [] }
            if !keys.contains(key) { keys.append(key) }
        } while scanner.take(UInt8(ascii: ","))
        return scanner.take(UInt8(ascii: "}")) ? keys : []
    }

    private struct Scanner {
        let bytes: [UInt8]
        var index = 0

        init(_ bytes: [UInt8]) {
            self.bytes = bytes
        }

        /// Takes `byte` after any whitespace, false when something else comes.
        mutating func take(_ byte: UInt8) -> Bool {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == byte else { return false }
            index += 1
            return true
        }

        /// A string literal, escapes decoded; nil when none comes.
        mutating func string() -> String? {
            skipWhitespace()
            let start = index
            guard skipString() else { return nil }
            let literal = Data(bytes[start ..< index])
            return (try? JSONSerialization.jsonObject(with: literal, options: [.fragmentsAllowed])) as? String
        }

        /// Steps over one value of any kind, nested ones included.
        mutating func skipValue() -> Bool {
            skipWhitespace()
            var depth = 0
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    guard skipString() else { return false }
                case UInt8(ascii: "{"), UInt8(ascii: "["):
                    depth += 1
                    index += 1
                case UInt8(ascii: "}"), UInt8(ascii: "]"):
                    // The object's own closing brace ends a bare value.
                    if depth == 0 { return true }
                    depth -= 1
                    index += 1
                case UInt8(ascii: ","):
                    if depth == 0 { return true }
                    index += 1
                default:
                    index += 1
                }
            }
            return depth == 0
        }

        private mutating func skipString() -> Bool {
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { return false }
            index += 1
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\\"):
                    index += 2
                case UInt8(ascii: "\""):
                    index += 1
                    return true
                default:
                    index += 1
                }
            }
            return false
        }

        private mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) {
                index += 1
            }
        }
    }
}

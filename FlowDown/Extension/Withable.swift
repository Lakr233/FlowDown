//
//  Withable.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import Foundation

public protocol Withable {}

extension Withable {
    @inlinable
    @discardableResult
    func with(_ block: (inout Self) throws -> Void) rethrows -> Self {
        var copy = self
        try block(&copy)
        return copy
    }
}

extension Withable where Self: AnyObject {
    @inlinable
    @discardableResult
    func with(_ block: (Self) throws -> Void) rethrows -> Self {
        try block(self)
        return self
    }
}

extension NSObject: Withable {}

extension Array: Withable {}
extension Dictionary: Withable {}
extension Set: Withable {}
extension JSONDecoder: Withable {}
extension JSONEncoder: Withable {}

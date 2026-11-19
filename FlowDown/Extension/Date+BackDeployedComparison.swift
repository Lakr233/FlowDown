//
//  Date+BackDeployedComparison.swift
//  FlowDown
//

import Foundation

// The Xcode 27.2 SDK declares Foundation's `Date >=` and `Date <=` as
// `@backDeployed(before: iOS 27.2, macOS 27.2)`. A caller then weak-imports
// the OS symbol and calls it directly once the OS reports 27.2, but iOS 27.2
// beta 24B5089g reports 27.2 without exporting it, so the call jumps to NULL.
// `Date <` is not back-deployed: write `!(a < b)` for `a >= b` and
// `!(b < a)` for `a <= b`.
//
// The MCP package (swift-sdk) still uses both operators in its OAuth and
// HTTP server code. Defining the two symbols here makes the linker bind those
// references inside the app instead of weak-importing them from Foundation.
// The bodies match Foundation's. Because these share Foundation's symbol
// names, a module that both calls these functions and uses `Date >=` or
// `Date <=` fails to compile; the app module must not use the operators.

@_silgen_name("$s10Foundation4DateV2geoiySbAC_ACtFZ")
public func _flowDownDateGreaterThanOrEqual(_ lhs: Date, _ rhs: Date) -> Bool {
    !(lhs < rhs)
}

@_silgen_name("$s10Foundation4DateV2leoiySbAC_ACtFZ")
public func _flowDownDateLessThanOrEqual(_ lhs: Date, _ rhs: Date) -> Bool {
    !(rhs < lhs)
}

//
//  WidgetsAttributes.swift
//  FlowDown
//
//  Created by qaq on 7/1/2026.
//

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)

    import ActivityKit
    import Foundation

    struct FlowDownWidgetsAttributes: ActivityAttributes {
        struct ContentState: Codable, Hashable {
            var conversationCount: Int
            var streamingSessionTextCount: Int
        }
    }

#endif

//
//  MCPError.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation

enum MCPError: Swift.Error, LocalizedError, Equatable {
    case connectionFailed
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            String(localized: "Invalid configuration.")
        case .connectionFailed:
            String(localized: "Unable to connect to the MCP server. Please check your network or server status.")
        }
    }
}

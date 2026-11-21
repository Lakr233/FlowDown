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
    /// The server answered 401 and the user has to sign in.
    case signInRequired(String)
    /// The server answered 401 and its authorization server needs a Client
    /// ID typed in before anyone can sign in.
    case clientIDRequired(String)
    /// The server answered 401 without advertising OAuth.
    case authorizationUnsupported(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            String(localized: "Invalid configuration.")
        case .connectionFailed:
            String(localized: "Unable to connect to the MCP server. Please check your network or server status.")
        case let .signInRequired(name):
            String(localized: "\(name) needs you to sign in. Go to Settings > Tools > MCP Tools and tap Sign In for this server.")
        case let .clientIDRequired(name):
            String(localized: "\(name) needs you to sign in, but can't set it up automatically. Enter a Client ID in this server's settings, then sign in.")
        case let .authorizationUnsupported(name):
            String(localized: "\(name) doesn't support sign-in. Fill in the Authorization field in this server's settings instead.")
        }
    }
}

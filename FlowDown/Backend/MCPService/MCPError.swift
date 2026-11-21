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
            String(localized: "\(name) requires sign-in. Sign in from the server's settings.")
        case let .clientIDRequired(name):
            String(localized: "\(name) requires sign-in, but its authorization server does not support automatic registration. Enter a Client ID in the server's settings.")
        case let .authorizationUnsupported(name):
            String(localized: "\(name) requires authorization but does not support OAuth sign-in. Add an Authorization header instead.")
        }
    }
}

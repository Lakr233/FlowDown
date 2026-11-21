//
//  ModelContextServer+Transport.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation
import MCP
import Storage

extension ModelContextServer {
    /// Builds the HTTP transport. With `oauth`, the transport attaches stored
    /// tokens and reports 401s to it — unless the configured headers carry
    /// an `Authorization` value, which always wins.
    func createTransport(oauth: MCPOAuthManager? = nil) throws -> HTTPClientTransport {
        guard let url = URL(string: endpoint) else {
            throw MCPError.invalidConfiguration
        }

        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme)
        else {
            throw MCPError.invalidConfiguration
        }

        let config = URLSessionConfiguration.default

        let headers = try? JSONDecoder().decode(
            [String: String].self,
            from: header.data(using: .utf8) ?? .init(),
        )
        config.timeoutIntervalForRequest = .init(timeout)
        config.timeoutIntervalForResource = .init(timeout)
        config.httpAdditionalHeaders = headers
        oauth?.configureSession(config)

        return HTTPClientTransport(
            endpoint: url,
            configuration: config,
            authorizer: oauth?.makeAuthorizer(for: self),
        )
    }
}

//
//  MCPTransportManager.swift
//  FlowDown
//
//  Created by Alan Ye on 7/10/25.
//

import Foundation
import MCP
import Storage

extension ModelContextServer {
    func createTransport() throws -> HTTPClientTransport {
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

        return HTTPClientTransport(endpoint: url, configuration: config)
    }
}

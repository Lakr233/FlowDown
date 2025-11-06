//
//  ToolCallRequest.swift
//  ChatClientKit
//
//  Created by 秋星桥 on 2/27/25.
//

import Foundation

public struct ToolCallRequest: Codable, Equatable, Hashable {
    public var id: UUID = .init()

    /// The model-assigned tool call id (Responses API function_call.call_id)
    public let callId: String?
    public let name: String
    public let args: String

    init(callId: String?, name: String, args: String) {
        self.callId = callId
        self.name = name
        self.args = args
    }
}

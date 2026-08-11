//
//  MTDeleteMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTDeleteMemoryTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "Delete Memory")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "delete_memory",
            description: "Delete a memory that is outdated or wrong. Get its ID from list_memories first.",
            parameters: [
                "type": "object",
                "properties": [
                    "memory_id": [
                        "type": "string",
                        "description": "Memory ID from list_memories.",
                    ],
                    "reason": [
                        "type": "string",
                        "description": "Why it is being deleted, e.g. outdated or incorrect.",
                    ],
                ],
                "required": ["memory_id", "reason"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "trash.circle",
            title: "Delete Memory",
            explain: "Allows AI to delete specific memories that are no longer needed.",
            key: "wiki.qaq.ModelTools.DeleteMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        guard let json = decodeArguments(input),
              let memoryId = json["memory_id"] as? String
        else {
            throw NSError(
                domain: "MTDeleteMemoryTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid parameters. memory_id is required."),
                ],
            )
        }

        let reason = json["reason"] as? String
        return await MemoryStore.shared.deleteMemory(id: memoryId, reason: reason)
    }
}

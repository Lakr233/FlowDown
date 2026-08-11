//
//  MTUpdateMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTUpdateMemoryTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "Update Memory")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "update_memory",
            description: """
            Replace a memory's content when the information changes or gets more specific. Get its ID from list_memories first.
            Keep the third person form ("User is a senior software engineer").
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "memory_id": [
                        "type": "string",
                        "description": "Memory ID from list_memories.",
                    ],
                    "new_content": [
                        "type": "string",
                        "description": "Replacement content, written in third person.",
                    ],
                ],
                "required": ["memory_id", "new_content"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "pencil.circle",
            title: "Update Memory",
            explain: "Allows AI to update existing memory content.",
            key: "wiki.qaq.ModelTools.UpdateMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        guard let json = decodeArguments(input),
              let memoryId = json["memory_id"] as? String,
              let newContent = json["new_content"] as? String
        else {
            throw NSError(
                domain: "MTUpdateMemoryTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid parameters. Both memory_id and new_content are required."),
                ],
            )
        }

        return await MemoryStore.shared.updateMemory(id: memoryId, newContent: newContent)
    }
}

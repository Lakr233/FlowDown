//
//  MTUpdateMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation

final class MTUpdateMemoryTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Update Memory")
    }

    var definition: ChatRequestBody.Tool {
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

    static var controlObject: ConfigurableObject {
        .init(
            icon: "pencil.circle",
            title: "Update Memory",
            explain: "Allows AI to update existing memory content.",
            key: "wiki.qaq.ModelTools.UpdateMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var group: ModelToolGroup? {
        .memory
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let memoryId = arguments.string("memory_id"),
              let newContent = arguments.string("new_content")
        else {
            throw ModelToolError.invalidArguments(
                String(localized: "Invalid parameters. Both memory_id and new_content are required."),
            )
        }

        return await ModelToolOutput(text: MemoryStore.shared.updateMemory(id: memoryId, newContent: newContent))
    }
}

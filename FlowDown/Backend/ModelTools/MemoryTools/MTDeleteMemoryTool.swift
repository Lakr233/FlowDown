//
//  MTDeleteMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation

final class MTDeleteMemoryTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Delete Memory")
    }

    var definition: ChatRequestBody.Tool {
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

    static var controlObject: ConfigurableObject {
        .init(
            icon: "trash.circle",
            title: "Delete Memory",
            explain: "Allows AI to delete specific memories that are no longer needed.",
            key: "wiki.qaq.ModelTools.DeleteMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var group: ModelToolGroup? {
        .memory
    }

    /// Declares its own `reason`, which the store records with the deletion;
    /// FlowDown leaves it on the arguments.
    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let memoryId = arguments.string("memory_id") else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid parameters. memory_id is required."))
        }

        let reason = arguments.string("reason")
        return await ModelToolOutput(text: MemoryStore.shared.deleteMemory(id: memoryId, reason: reason))
    }
}

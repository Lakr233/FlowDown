//
//  MTListMemoriesTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation

final class MTListMemoriesTool: ConfigurableModelTool, @unchecked Sendable {
    private static let defaultLimit = 20

    var interfaceName: String {
        String(localized: "List Memories")
    }

    var definition: ChatRequestBody.Tool {
        let maxLimit = MemoryStore.memoryLimitRange.upperBound
        return .function(
            name: "list_memories",
            description: "List stored memories with their IDs, which update_memory and delete_memory require.",
            parameters: [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "number",
                        "description": .string(
                            "How many memories to return (default \(Self.defaultLimit), max \(maxLimit)).",
                        ),
                    ],
                ],
                "required": ["limit"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "list.bullet.clipboard",
            title: "List Memories",
            explain: "Allows AI to list memories with IDs for management operations.",
            key: "wiki.qaq.ModelTools.ListMemoriesTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var group: ModelToolGroup? {
        .memory
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        let limit = arguments["limit"] as? Int ?? Self.defaultLimit
        return await ModelToolOutput(text: MemoryStore.shared.listToolText(limit: limit))
    }
}

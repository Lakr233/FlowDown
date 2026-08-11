//
//  MTListMemoriesTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTListMemoriesTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "List Memories")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "list_memories",
            description: "List stored memories with their IDs, which update_memory and delete_memory require.",
            parameters: [
                "type": "object",
                "properties": [
                    "limit": [
                        "type": "number",
                        "description": "How many memories to return (default 20, max 100).",
                    ],
                ],
                "required": ["limit"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "list.bullet.clipboard",
            title: "List Memories",
            explain: "Allows AI to list memories with IDs for management operations.",
            key: "wiki.qaq.ModelTools.ListMemoriesTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        var limit = 20

        if let json = decodeArguments(input),
           let limitValue = json["limit"] as? Int
        {
            limit = min(max(limitValue, 1), 100) // Ensure between 1 and 100
        }

        return await MemoryStore.shared.listMemoriesWithIds(limit: limit)
    }
}

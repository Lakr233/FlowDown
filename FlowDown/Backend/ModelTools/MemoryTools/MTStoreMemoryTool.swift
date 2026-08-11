//
//  MTStoreMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTStoreMemoryTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "Store Memory")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "store_memory",
            description: """
            Save information worth recalling in later conversations: preferences, project details, goals, feedback.
            Store it proactively, in the user's language, written in third person ("User is a student", not "I'm a student").
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "content": [
                        "type": "string",
                        "description": "The fact to store, third person and specific, e.g. 'User prefers detailed explanations'.",
                    ],
                ],
                "required": ["content"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "square.and.arrow.down",
            title: "Store Memory",
            explain: "Allows AI to store important information for future conversations.",
            key: "wiki.qaq.ModelTools.StoreMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        guard let json = decodeArguments(input),
              let content = json["content"] as? String
        else {
            throw NSError(
                domain: "MTStoreMemoryTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid memory content"),
                ],
            )
        }

        await MemoryStore.shared.store(content: content)

        return String(localized: "Memory stored successfully: \(content)")
    }
}

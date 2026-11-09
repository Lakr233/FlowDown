//
//  MTStoreMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation

final class MTStoreMemoryTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Store Memory")
    }

    var definition: ChatRequestBody.Tool {
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

    static var controlObject: ConfigurableObject {
        .init(
            icon: "square.and.arrow.down",
            title: "Store Memory",
            explain: "Allows AI to store important information for future conversations.",
            key: "wiki.qaq.ModelTools.StoreMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var group: ModelToolGroup? {
        .memory
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let content = arguments.string("content") else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid memory content"))
        }

        // Await the insert so a rejected or failed store reaches the model as a
        // tool failure instead of a false success.
        do {
            _ = try await MemoryStore.shared.storeAsync(content: content)
        } catch MemoryStoreError.invalidContent(_) {
            throw ModelToolError.invalidArguments(String(localized: "Invalid memory content"))
        }

        return ModelToolOutput(text: String(localized: "Memory stored successfully: \(content)"))
    }
}

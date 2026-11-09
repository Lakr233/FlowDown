//
//  MTRecallMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation

final class MTRecallMemoryTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Recall Memory")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "recall_memory",
            description: "Retrieve every stored memory for context about the user's preferences, projects and history.",
            parameters: [
                "type": "object",
                "properties": [:],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "square.and.arrow.up",
            title: "Recall Memory",
            explain: "Allows AI to retrieve stored memories for context.",
            key: "wiki.qaq.ModelTools.RecallMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    var group: ModelToolGroup? {
        .memory
    }

    func execute(_: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        await ModelToolOutput(text: MemoryStore.shared.recallToolText())
    }
}

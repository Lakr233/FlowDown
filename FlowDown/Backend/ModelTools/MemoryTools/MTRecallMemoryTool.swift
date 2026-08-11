//
//  MTRecallMemoryTool.swift
//  FlowDown
//
//  Created by Alan Ye on 8/14/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import UIKit

class MTRecallMemoryTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "Recall Memory")
    }

    override var definition: ChatRequestBody.Tool {
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

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "square.and.arrow.up",
            title: "Recall Memory",
            explain: "Allows AI to retrieve stored memories for context.",
            key: "wiki.qaq.ModelTools.RecallMemoryTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with _: String, anchorTo _: UIView) async throws -> String {
        await MemoryStore.shared.getAllMemories()
    }
}

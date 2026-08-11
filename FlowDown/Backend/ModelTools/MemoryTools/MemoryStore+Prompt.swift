//
//  MemoryStore+Prompt.swift
//  FlowDown
//
//  Created by qaq on 7/11/2025.
//

import Foundation

nonisolated extension MemoryStore {
    static let memoryToolsPrompt: String =
        """
        Memory tools: store_memory saves durable facts about the user — personal details, project context, preferences, goals — as soon as they surface. Write every memory in third person ("User prefers concise responses"). recall_memory brings that context back; list_memories, update_memory and delete_memory keep it accurate through memory IDs.
        """
}

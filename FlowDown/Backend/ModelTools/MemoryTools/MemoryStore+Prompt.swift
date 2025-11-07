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
        Memory Tools Available:

        STORE MEMORY - Use store_memory proactively to save important user information like:
        • Personal details: "User is a software engineer", "User prefers dark mode"
        • Project context: "Working on iOS app called FlowDown", "Using Swift and UIKit"
        • Preferences: "User likes detailed explanations", "User prefers concise responses"
        • Goals: "Learning Swift", "Building a chat application"
        • Important facts: "User's timezone is PST", "User works remotely"

        FORMAT: Store memories in third person format (e.g., "User is a student" not "I'm a student")
        WHEN: Immediately when user shares personal info, preferences, or important context

        RECALL MEMORY - Use recall_memory to get context:
        • At conversation start to understand user background
        • When you need context about user preferences or past discussions
        • Before making recommendations to personalize them

        MANAGE MEMORY - Use list_memories, update_memory, delete_memory to maintain accuracy:
        • List memories when you need to update or remove specific information
        • Update memories when information changes or becomes more specific
        • Delete memories when information becomes outdated or incorrect

        Be proactive about memory management to provide personalized, contextually aware assistance. Always format stored information clearly and in third person perspective.
        """
}

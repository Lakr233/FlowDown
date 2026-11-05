//
//  MessageListView+ActivitySummary.swift
//  FlowDown
//

import Foundation
import Storage

extension MessageListView {
    /// The thoughts and tool calls between two pieces of the conversation,
    /// folded into one line ("Thought for 8 seconds and called 2 tools").
    /// Tapping it opens the trace, which lists every step in order.
    ///
    /// Built from the stored messages as they are: an assistant message's
    /// reasoning is a thought, a tool hint is a call, and any reply text,
    /// user message or other row ends the summary.
    struct ActivitySummary: Identifiable, Hashable {
        enum Step: Hashable {
            case thought(Message.ID, text: String)
            case tool(Message.ID, status: Message.ToolStatus)

            var id: String {
                switch self {
                case let .thought(messageID, _): "Thought.\(messageID)"
                case let .tool(messageID, status): "Tool.\(messageID).\(status.id)"
                }
            }
        }

        /// From the first message folded in, so the row keeps its identity
        /// while the turn adds steps.
        let id: String
        var steps: [Step] = []
        var thinkingDuration: TimeInterval = 0
        /// The turn is still at work on this summary: nothing has come after it.
        var isRunning = false

        init(startingWith messageID: Message.ID) {
            id = "Activity.\(messageID)"
        }

        var tools: Int {
            steps.count { if case .tool = $0 { true } else { false } }
        }

        var runningTools: Int {
            steps.count { if case let .tool(_, status) = $0 { status.state == 0 } else { false } }
        }

        var hasThoughts: Bool {
            steps.contains { if case .thought = $0 { true } else { false } }
        }

        /// Whole seconds spent thinking; at least one once there is a thought.
        var seconds: Int {
            let seconds = Int(thinkingDuration.rounded())
            return hasThoughts ? max(1, seconds) : seconds
        }

        /// The newest running call's name, shown under a running summary. Once
        /// the calls are done the model is thinking again and it goes away.
        var banner: String? {
            guard isRunning else { return nil }
            for step in steps.reversed() {
                if case let .tool(_, status) = step, status.state == 0 {
                    return status.name
                }
            }
            return nil
        }

        var title: String {
            // An unfinished summary counts only the calls still running; between
            // them the model is at work again, so it reads "Thinking…".
            if isRunning {
                let running = runningTools
                guard running > 0 else { return String(localized: "Thinking…") }
                return running == 1
                    ? String(localized: "Executing tool…")
                    : String(localized: "Executing \(running) tools…")
            }
            let seconds = seconds
            let tools = tools
            if seconds <= 0 {
                return tools == 1 ? String(localized: "Called 1 tool") : String(localized: "Called \(tools) tools")
            }
            if tools <= 0 {
                return seconds == 1
                    ? String(localized: "Thought for 1 second")
                    : String(localized: "Thought for \(seconds) seconds")
            }
            if seconds == 1 {
                return tools == 1
                    ? String(localized: "Thought for 1 second and called 1 tool")
                    : String(localized: "Thought for 1 second and called \(tools) tools")
            }
            return tools == 1
                ? String(localized: "Thought for \(seconds) seconds and called 1 tool")
                : String(localized: "Thought for \(seconds) seconds and called \(tools) tools")
        }
    }
}

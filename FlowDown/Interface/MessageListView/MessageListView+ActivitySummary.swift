//
//  MessageListView+ActivitySummary.swift
//  FlowDown
//

import Foundation
import Storage

extension MessageListView {
    /// The thoughts, tool calls and web searches between two pieces of the
    /// conversation, folded into one line ("Thought for 8 seconds and called
    /// 2 tools"). Tapping it opens the trace, which lists every step in order.
    ///
    /// Built from the stored messages as they are: an assistant message's
    /// reasoning is a thought, a tool hint is a call, a web search row is a
    /// search that counts as a call, and any reply text, user message or
    /// other row ends the summary.
    struct ActivitySummary: Identifiable, Hashable {
        enum Step: Hashable {
            case thought(Message.ID, text: String)
            case tool(Message.ID, status: Message.ToolStatus)
            /// `isInterrupted`: left unfinished, and nothing is at work on it.
            case webSearch(Message.ID, status: Message.WebSearchStatus, isInterrupted: Bool)

            var id: String {
                switch self {
                case let .thought(messageID, _): "Thought.\(messageID)"
                case let .tool(messageID, status): "Tool.\(messageID).\(status.id)"
                case let .webSearch(messageID, _, _): "WebSearch.\(messageID)"
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
        /// The reason each running call gave, by its row; with `showsSteps`,
        /// every call's.
        var reasons: [Message.ID: String] = [:]
        /// Every step is listed under the title (`InlineActivityStepsSetting`),
        /// so the newest call's banner is not shown on top of them.
        var showsSteps = false

        init(startingWith messageID: Message.ID) {
            id = "Activity.\(messageID)"
        }

        var tools: Int {
            steps.count {
                switch $0 {
                case .tool, .webSearch: true
                case .thought: false
                }
            }
        }

        var runningTools: Int {
            steps.count {
                switch $0 {
                case let .tool(_, status): status.state == 0
                case let .webSearch(_, status, _): status.isUnfinished
                case .thought: false
                }
            }
        }

        var hasThoughts: Bool {
            steps.contains { if case .thought = $0 { true } else { false } }
        }

        /// Whole seconds spent thinking; at least one once there is a thought.
        var seconds: Int {
            let seconds = Int(thinkingDuration.rounded())
            return hasThoughts ? max(1, seconds) : seconds
        }

        /// The newest running call's reason, else its name, or a running
        /// search's progress, shown under a running summary. Once the calls
        /// are done the model is thinking again and it goes away.
        var banner: String? {
            guard isRunning, !showsSteps else { return nil }
            for step in steps.reversed() {
                switch step {
                case let .tool(messageID, status) where status.state == 0:
                    return reasons[messageID] ?? status.name
                case let .webSearch(_, status, _) where status.isUnfinished:
                    return status.statusText()
                default:
                    continue
                }
            }
            return nil
        }

        /// A step as the row lists it under the title with `showsSteps`.
        struct InlineStep: Hashable {
            enum Kind: Hashable {
                /// Its whole text, wrapped.
                case thought
                /// One line, what the banner says for it while it runs.
                case call
            }

            let id: String
            let kind: Kind
            let text: String
        }

        /// Every step in order, empty unless `showsSteps`: a thought's text;
        /// a call's reason, else its name; a search's queries and its
        /// progress, or how it went, as its trace shows them.
        var inlineSteps: [InlineStep] {
            guard showsSteps else { return [] }
            return steps.map { step in
                switch step {
                case let .thought(_, text):
                    InlineStep(id: step.id, kind: .thought, text: text)
                case let .tool(messageID, status):
                    InlineStep(id: step.id, kind: .call, text: Self.line(reasons[messageID] ?? status.name))
                case let .webSearch(_, status, isInterrupted):
                    InlineStep(id: step.id, kind: .call, text: Self.line(status.traceLine(isInterrupted: isInterrupted)))
                }
            }
        }

        /// `text` on one line, as the banner shows it.
        private static func line(_ text: String) -> String {
            text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }

        /// A search still unfinished once nothing is at work on the summary
        /// was cut off: the session stopped, or the app did.
        mutating func settleSearches() {
            steps = steps.map { step in
                guard case let .webSearch(messageID, status, _) = step, status.isUnfinished else { return step }
                return .webSearch(messageID, status: status, isInterrupted: true)
            }
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

extension Message.WebSearchStatus {
    /// Neither done (1) nor failed (negative).
    var isUnfinished: Bool {
        (0 ..< 1).contains(proccessProgress)
    }

    /// Its queries, then what it is at or how it ended, as its trace and a
    /// summary that lists its steps show it: "query · Browsed 6 website(s)".
    func traceLine(isInterrupted: Bool = false) -> String {
        (queries + [statusText(isInterrupted: isInterrupted)]).joined(separator: " · ")
    }

    /// What the search is at, or how it ended, on one line.
    func statusText(isInterrupted: Bool = false) -> String {
        if proccessProgress < 0 {
            return String(localized: "Failed to search")
        }
        if numberOfResults > 0 {
            return String(localized: "Browsed \(numberOfResults) website(s)")
        }
        if isInterrupted {
            return String(localized: "Tool call was interrupted.")
        }
        if proccessProgress >= 1 {
            return String(localized: "Search completed with no results")
        }
        if proccessProgress > 0, numberOfWebsites > 0 {
            return String(localized: "Searched \(numberOfWebsites) website(s), fetching them") + "..."
        }
        if queries.indices.contains(currentQuery) {
            let keyword = queries[currentQuery]
            return String(localized: "Browsing \(keyword)") + "..."
        }
        return String(localized: "Determining search keywords") + "..."
    }
}

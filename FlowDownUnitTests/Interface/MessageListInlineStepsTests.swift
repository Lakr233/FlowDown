//
//  MessageListInlineStepsTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@preconcurrency @testable import FlowDown
import Foundation
import MarkdownView
import Storage
import Testing
import UIKit

/// Summaries that list their steps under the title (`InlineActivityStepsSetting`).
@Suite(.serialized)
struct MessageListInlineStepsTests {
    // MARK: - Entries

    @Test
    @MainActor
    func `with the setting off a summary is what it always was`() async throws {
        try await withTurn(running: true) { session, ids in
            let listView = MessageListView()
            listView.session = session
            let unchanged = listView.entries(from: session.messages, isExecuting: true)
            let off = listView.entries(from: session.messages, isExecuting: true, showsSteps: false)
            #expect(off == unchanged)

            let summary = try #require(summaries(in: off).first)
            #expect(!summary.showsSteps)
            #expect(summary.inlineSteps.isEmpty)
            #expect(summary.title == String(localized: "Executing tool…"))
            // Only the running call's reason, under the title.
            #expect(summary.reasons == [ids.runningCall: "Read the second page"])
            #expect(summary.banner == "Read the second page")

            let font = UIFont.preferredFont(forTextStyle: .body)
            let footnote = UIFont.preferredFont(forTextStyle: .footnote)
            let height = ActivitySummaryView.height(for: summary, font: font, stepFont: footnote, width: 320)
            #expect(height == ActivitySummaryView.headerHeight(font: font)
                + ActivitySummaryView.bannerSpacing + MessageBannerView.height)
        }
    }

    @Test
    @MainActor
    func `with the setting on every step is listed in order and the banner goes`() async throws {
        try await withTurn(running: true) { session, ids in
            let listView = MessageListView()
            listView.session = session
            let entries = listView.entries(from: session.messages, isExecuting: true, showsSteps: true)
            let summary = try #require(summaries(in: entries).first)

            #expect(summary.showsSteps)
            #expect(summary.isRunning)
            #expect(summary.title == String(localized: "Executing tool…"))
            #expect(summary.banner == nil)
            let searched = "launch date · " + String(localized: "Browsed \(2) website(s)")
            #expect(summary.inlineSteps.map(\.kind) == [.thought, .call, .call, .thought, .call])
            #expect(summary.inlineSteps.map(\.text) == [
                "Look the dates up first.\n\nThen compare.",
                "Find the dates",
                searched,
                "One more page.",
                "Read the second page",
            ])
            #expect(summary.inlineSteps.map(\.id) == summary.steps.map(\.id))
            #expect(summary.reasons[ids.finishedCall] == "Find the dates")
        }
    }

    @Test
    @MainActor
    func `a call without a reason is listed by its name`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Go")
            }
            let call = session.appendNewMessage(role: .toolHint)
            session.encodeToolRequestAndAttachToToolMessage(ToolRequest(name: "fetch", args: #"{"url":"https://example.com"}"#), message: call)
            call.update(\.toolStatus, to: .init(name: "Fetch Page", state: 1, message: "Done."))

            let listView = MessageListView()
            listView.session = session
            let summary = try #require(summaries(in: listView.entries(from: session.messages, isExecuting: false, showsSteps: true)).first)
            #expect(summary.inlineSteps.map(\.text) == ["Fetch Page"])
        }
    }

    @Test
    func `a search is listed by its queries and how it went as its trace shows it`() {
        func line(_ status: Message.WebSearchStatus, isInterrupted: Bool = false) -> String? {
            var summary = MessageListView.ActivitySummary(startingWith: "s")
            summary.steps = [.webSearch("s", status: status, isInterrupted: isInterrupted)]
            summary.showsSteps = true
            let text = summary.inlineSteps.first?.text
            // The line the trace sheet shows under "Web Search".
            let trace = TraceStep(summary.steps[0], arguments: nil).subtitle
            #expect(text == trace)
            #expect(summary.inlineSteps.first?.kind == .call)
            return text
        }

        var browsed = Message.WebSearchStatus()
        browsed.queries = ["科技新闻 2026年11月11日 今日头条"]
        browsed.numberOfResults = 6
        browsed.proccessProgress = 1
        #expect(line(browsed) == "科技新闻 2026年11月11日 今日头条 · " + String(localized: "Browsed \(6) website(s)"))

        var running = Message.WebSearchStatus()
        running.queries = ["科技新闻 今日", "AI news"]
        running.currentQuery = 1
        running.proccessProgress = 0
        let current = "AI news"
        #expect(line(running) == "科技新闻 今日 · AI news · " + String(localized: "Browsing \(current)") + "...")

        var interrupted = Message.WebSearchStatus()
        interrupted.queries = ["weather"]
        #expect(line(interrupted, isInterrupted: true) == "weather · " + String(localized: "Tool call was interrupted."))

        var failed = Message.WebSearchStatus()
        failed.queries = ["weather"]
        failed.proccessProgress = -1
        #expect(line(failed) == "weather · " + String(localized: "Failed to search"))

        // Before it has a query, only how it is going.
        #expect(line(Message.WebSearchStatus()) == String(localized: "Determining search keywords") + "...")

        // A query over several lines still lists on one.
        var multiline = browsed
        multiline.queries = ["first\n  second"]
        #expect(line(multiline) == "first second · " + String(localized: "Browsed \(6) website(s)"))
    }

    @Test
    @MainActor
    func `a search with a long query is one line cut at its end`() throws {
        var status = Message.WebSearchStatus()
        status.queries = [String(repeating: "a very long search query ", count: 20)]
        status.numberOfResults = 8
        status.proccessProgress = 1
        var summary = MessageListView.ActivitySummary(startingWith: "s")
        summary.steps = [.webSearch("s", status: status, isInterrupted: false)]
        summary.showsSteps = true

        let theme = MessageListView().theme
        let width: CGFloat = 300
        let font = theme.fonts.footnote
        let step = try #require(summary.inlineSteps.first)
        let stepHeight = ActivityStepText.height(of: step, font: font, width: width)
        let oneLine = ActivityStepText.height(of: "a", wraps: false, font: font, width: width)
        #expect(stepHeight == oneLine)

        let row = ActivitySummaryView(frame: .zero)
        row.theme = theme
        row.show(summary)
        let height = ActivitySummaryView.height(for: summary, font: theme.fonts.body, stepFont: font, width: width)
        row.frame = CGRect(x: 0, y: 0, width: width, height: height)
        row.layoutIfNeeded()
        let labels = row.contentView.subviews
            .filter { !($0 is ThinkingStatusLabel) }
            .compactMap { $0 as? UILabel }
            .filter { !$0.isHidden }
        #expect(labels.count == 1)
        let label = labels.first
        #expect(label?.numberOfLines == 1)
        #expect(label?.lineBreakMode == .byTruncatingTail)
        #expect(label?.frame.height == oneLine)
        #expect(label?.text?.hasPrefix("a very long search query") == true)
    }

    @Test
    @MainActor
    func `turning the setting on changes the entry but not the row`() async throws {
        try await withTurn(running: false) { session, _ in
            let listView = MessageListView()
            listView.session = session
            let off = listView.entries(from: session.messages, isExecuting: false, showsSteps: false)
            let on = listView.entries(from: session.messages, isExecuting: false, showsSteps: true)

            #expect(off.map(\.id) == on.map(\.id))
            let offEntry = try #require(off.first { if case .activity = $0 { true } else { false } })
            let onEntry = try #require(on.first { if case .activity = $0 { true } else { false } })
            #expect(offEntry != onEntry)
            #expect(offEntry.hashValue != onEntry.hashValue)
            // Everything else is the same.
            #expect(off.filter { if case .activity = $0 { false } else { true } }
                == on.filter { if case .activity = $0 { false } else { true } })
        }
    }

    @Test
    @MainActor
    func `a finished summary lists its steps under its usual title`() async throws {
        try await withTurn(running: false) { session, _ in
            let listView = MessageListView()
            listView.session = session
            let summary = try #require(summaries(in: listView.entries(from: session.messages, isExecuting: false, showsSteps: true)).first)
            #expect(!summary.isRunning)
            #expect(summary.title == String(localized: "Thought for \(5) seconds and called \(3) tools"))
            #expect(summary.inlineSteps.count == 5)
            #expect(summary.banner == nil)
        }
    }

    @Test
    func `a reason is decoded once for each row`() {
        let cache = MessageListView.ToolReasonCache()
        let message = Message(deviceId: "test")
        var decodes = 0
        for _ in 0 ..< 3 {
            let reason = cache.reason(for: message) { _ in
                decodes += 1
                return #"{"reason":"  Check it  "}"#
            }
            #expect(reason == "Check it")
        }
        #expect(decodes == 1)
    }

    // MARK: - Streaming

    @Test
    func `a growing thought shows a few times a second and always ends in full`() {
        var throttle = MessageListView.InlineThoughtThrottle()
        func entries(_ text: String, running: Bool = true, showsSteps: Bool = true) -> [MessageListView.Entry] {
            var summary = MessageListView.ActivitySummary(startingWith: "m")
            summary.steps = [.thought("m", text: text)]
            summary.isRunning = running
            summary.showsSteps = showsSteps
            return [.activity(summary)]
        }
        func shownText(_ entries: [MessageListView.Entry]) -> String? {
            guard case let .activity(summary)? = entries.first,
                  case let .thought(_, text)? = summary.steps.first
            else { return nil }
            return text
        }
        let interval = MessageListView.InlineThoughtThrottle.interval

        var first = entries("A")
        #expect(throttle.apply(to: &first, now: 10) == nil)
        #expect(shownText(first) == "A")

        var soon = entries("AB")
        let wait = throttle.apply(to: &soon, now: 10 + interval / 2)
        #expect(shownText(soon) == "A")
        #expect(wait != nil)
        #expect(abs((wait ?? 0) - interval / 2) < 0.0001)

        var later = entries("ABC")
        #expect(throttle.apply(to: &later, now: 10 + interval + 0.001) == nil)
        #expect(shownText(later) == "ABC")

        // Not the shown text grown: shown at once.
        var replaced = entries("X")
        #expect(throttle.apply(to: &replaced, now: 10 + interval + 0.01) == nil)
        #expect(shownText(replaced) == "X")

        // Once the summary stops running, all of it at once.
        var finished = entries("XYZ", running: false)
        #expect(throttle.apply(to: &finished, now: 10 + interval + 0.02) == nil)
        #expect(shownText(finished) == "XYZ")

        // With the setting off nothing is held back.
        var plain = entries("Q", showsSteps: false)
        var grown = entries("QR", showsSteps: false)
        _ = throttle.apply(to: &plain, now: 20)
        #expect(throttle.apply(to: &grown, now: 20.01) == nil)
        #expect(shownText(grown) == "QR")
    }

    @Test
    @MainActor
    func `a flush shows what the last notification brought and never reads the messages again`() async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "Think")
            }
            let thought = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "First")
            }
            let listView = MessageListView()
            listView.session = session
            // A notification: the entries are built from the messages then.
            func notification() -> MessageListView.InlineStepsUpstream.Snapshot {
                .init(
                    entries: listView.entries(from: session.messages, isExecuting: true, showsSteps: true),
                    scrolling: true,
                    isLoading: "Loading",
                )
            }
            func thoughtText(_ entries: [MessageListView.Entry]) -> String? {
                guard let summary = summaries(in: entries).first,
                      case let .thought(_, text)? = summary.steps.first
                else { return nil }
                return text
            }
            let interval = MessageListView.InlineThoughtThrottle.interval
            var upstream = MessageListView.InlineStepsUpstream()
            let none = upstream.flush(now: 0) == nil
            #expect(none)

            let first = notification()
            #expect(summaries(in: first.entries).first?.isRunning == true)
            let shownFirst = upstream.receive(first, now: 10)
            #expect(thoughtText(shownFirst.entries) == "First")

            // Grown within the interval: held back, a flush due.
            thought.update(\.reasoningContent, to: "First, then")
            let held = upstream.receive(notification(), now: 10 + interval / 2)
            #expect(thoughtText(held.entries) == "First")
            #expect(held.wait != nil)

            // The stream writes on after the notification was taken.
            thought.update(\.reasoningContent, to: "First, then more")
            let flush = upstream.flush(now: 10 + interval + 0.01)
            let flushed = try #require(flush)
            #expect(thoughtText(flushed.entries) == "First, then")
            #expect(flushed.wait == nil)
            #expect(flushed.snapshot.scrolling)
            #expect(flushed.snapshot.isLoading == "Loading")
            // The flush's entries are the captured ones, held text released.
            #expect(flushed.entries == flushed.snapshot.entries)

            // The next notification brings the rest.
            let next = upstream.receive(notification(), now: 10 + 2 * interval + 0.02)
            #expect(thoughtText(next.entries) == "First, then more")

            // With the setting off there is nothing to flush.
            upstream.clear()
            let afterClear = upstream.flush(now: 20) == nil
            #expect(afterClear)
            _ = upstream.receive(notification(), now: 30)
            upstream.reset()
            let afterReset = upstream.flush(now: 31) == nil
            #expect(afterReset)
        }
    }

    @Test
    func `a long thought is set in pieces that stay put as it grows`() {
        let paragraph = String(repeating: "word ", count: 120) // 600 bytes
        var text = (0 ..< 6).map { "\(paragraph)\($0)" }.joined(separator: "\n\n")
        let pieces = ActivityStepText.pieces(of: text)
        #expect(pieces.count > 1)
        // The break between two pieces is left out; the rest of its run
        // starts the next piece.
        #expect(pieces.joined(separator: "\n") == text)
        #expect(pieces.dropFirst().allSatisfy { $0.hasPrefix("\n") })

        text += "\n\nmore and more"
        let grown = ActivityStepText.pieces(of: text)
        #expect(Array(grown.prefix(pieces.count - 1)) == Array(pieces.dropLast()))
        #expect(grown.joined(separator: "\n") == text)

        #expect(ActivityStepText.pieces(of: "short\n\ntext") == ["short\n\ntext"])
    }

    // MARK: - Row

    @Test
    @MainActor
    func `a row lists its steps at the height it was measured at`() async throws {
        try await withTurn(running: true) { session, _ in
            let listView = MessageListView()
            listView.session = session
            let summary = try #require(summaries(in: listView.entries(from: session.messages, isExecuting: true, showsSteps: true)).first)
            let theme = listView.theme
            let listWidth: CGFloat = 390
            let insets = MessageListView.listRowInsets(for: listWidth)
            let width = listWidth - insets.horizontal
            let height = ActivitySummaryView.height(
                for: summary,
                font: theme.fonts.body,
                stepFont: theme.fonts.footnote,
                width: width,
            )

            let row = ActivitySummaryView(frame: .zero)
            row.theme = theme
            row.show(summary)
            row.frame = CGRect(x: 0, y: 0, width: listWidth, height: height + insets.bottom)
            row.layoutIfNeeded()

            func stepLabels() -> [UILabel] {
                row.contentView.subviews
                    .filter { !($0 is ThinkingStatusLabel) }
                    .compactMap { $0 as? UILabel }
            }
            let labels = stepLabels().filter { !$0.isHidden }
            #expect(labels.count == 5)
            #expect(labels.map { $0.text ?? "" } == summary.inlineSteps.map(\.text))
            #expect(labels.allSatisfy { $0.font == theme.fonts.footnote })
            #expect(labels.allSatisfy { $0.frame.minX == 0 && $0.frame.width == width })
            let header = ActivitySummaryView.headerHeight(font: theme.fonts.body)
            #expect(labels.first?.frame.minY == header + ActivitySummaryView.bannerSpacing)
            for (above, below) in zip(labels, labels.dropFirst()) {
                #expect(below.frame.minY == above.frame.maxY + ActivitySummaryView.bannerSpacing)
            }
            #expect(labels.last?.frame.maxY == height)

            // Taken for a summary without steps, the row lists none.
            var plain = summary
            plain.showsSteps = false
            row.show(plain)
            row.layoutIfNeeded()
            let allHidden = stepLabels().allSatisfy { $0.isHidden }
            #expect(allHidden)
        }
    }
}

private extension MessageListInlineStepsTests {
    struct TurnIDs {
        let finishedCall: Message.ID
        let runningCall: Message.ID
    }

    func summaries(in entries: [MessageListView.Entry]) -> [MessageListView.ActivitySummary] {
        entries.compactMap { if case let .activity(summary) = $0 { summary } else { nil } }
    }

    /// A question, then a thought, a call with a reason, a search, another
    /// thought and a second call: still running, or finished and answered.
    @MainActor
    func withTurn(
        running: Bool,
        _ body: @MainActor (ConversationSession, TurnIDs) async throws -> Void,
    ) async throws {
        try await withTemporarySession { session in
            _ = session.appendNewMessage(role: .user) {
                $0.update(\.document, to: "When is it?")
            }
            let thought = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "  Look the dates up first.\n\nThen compare.\n")
                $0.update(\.thinkingDuration, to: 3)
                $0.update(\.document, to: String(localized: "Thinking finished without output any content."))
            }
            session.markDocumentAsPlaceholder(thought)
            let finished = session.appendNewMessage(role: .toolHint)
            session.encodeToolRequestAndAttachToToolMessage(
                ToolRequest(name: "search_calendar", args: #"{"query":"launch","reason":"Find the dates"}"#),
                message: finished,
            )
            finished.update(\.toolStatus, to: .init(name: "Search Calendar", state: 1, message: "Found 2."))
            _ = session.appendNewMessage(role: .webSearch) {
                var status = Message.WebSearchStatus()
                status.queries = ["launch date"]
                status.numberOfResults = 2
                status.proccessProgress = 1
                $0.update(\.webSearchStatus, to: status)
            }
            let second = session.appendNewMessage(role: .assistant) {
                $0.update(\.reasoningContent, to: "One more page.")
                $0.update(\.thinkingDuration, to: 2)
                $0.update(\.document, to: String(localized: "Thinking finished without output any content."))
            }
            session.markDocumentAsPlaceholder(second)
            let call = session.appendNewMessage(role: .toolHint)
            session.encodeToolRequestAndAttachToToolMessage(
                ToolRequest(name: "read_page", args: #"{"url":"https://example.com/2","reason":"Read the second page"}"#),
                message: call,
            )
            call.update(\.toolStatus, to: .init(name: "Read Page", state: running ? 0 : 1, message: running ? "" : "Done."))
            if !running {
                _ = session.appendNewMessage(role: .assistant) {
                    $0.update(\.document, to: "It is on Friday.")
                }
            }
            try await body(session, TurnIDs(finishedCall: finished.objectId, runningCall: call.objectId))
        }
    }

    @MainActor
    func withTemporarySession(
        _ body: @MainActor (ConversationSession) async throws -> Void,
    ) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let conversation = sdb.conversationMake { conversation in
            conversation.update(\.title, to: "Inline Steps \(UUID().uuidString.prefix(8))")
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        do {
            try await body(session)
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
        } catch {
            ConversationManager.shared.deleteConversation(identifier: conversation.id)
            throw error
        }
    }
}

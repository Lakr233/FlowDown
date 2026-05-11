@testable import ChatClientKit
@testable import FlowDown
import Foundation
@testable import Storage
import Testing

/// Live, network-touching coverage that proves each Reminders tool's JSON
/// schema is concrete enough that the backing model produces a syntactically
/// valid tool call against it. This catches regressions where adding new
/// schema fields (e.g. `clear_*` flags) makes the tool unusable by the LLM.
///
/// The model only sees the tool definitions; we never let it execute against
/// real EventKit. Tool outputs are stubbed with placeholder strings.
@Suite(.serialized)
struct OnlineReminderToolsE2ETests {
    static let responseFormats = OnlineE2ETestSupport.responseFormats

    // MARK: Client factory

    private func makeClient(for responseFormat: CloudModel.ResponseFormat) throws -> any ChatService {
        switch responseFormat {
        case .chatCompletions:
            return try OnlineE2ETestSupport.makeCompletionsClient()
        case .responses:
            return try OnlineE2ETestSupport.makeResponsesClient()
        }
    }

    private func collect(
        _ client: any ChatService,
        body: ChatRequestBody,
    ) async throws -> ChatResponse {
        try await retryingTransientErrors {
            let stream = try await client.streamingChat(body: body)
            var chunks: [ChatResponseChunk] = []
            for try await chunk in stream {
                chunks.append(chunk)
            }
            return ChatResponse(chunks: chunks)
        }
    }

    private func retryingTransientErrors<T>(
        maxAttempts: Int = 3,
        operation: @escaping () async throws -> T,
    ) async throws -> T {
        precondition(maxAttempts > 0)
        var lastError: Error?
        for attempt in 1 ... maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                guard attempt < maxAttempts, isTransientNetworkError(error) else { throw error }
                try await Task.sleep(for: .seconds(Double(attempt)))
            }
        }
        throw lastError ?? CancellationError()
    }

    private func isTransientNetworkError(_ error: Error) -> Bool {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            return [
                NSURLErrorTimedOut,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorCannotFindHost,
                NSURLErrorDNSLookupFailed,
                NSURLErrorResourceUnavailable,
            ].contains(ns.code)
        }
        if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? Error {
            return isTransientNetworkError(underlying)
        }
        return false
    }

    private func parsedArgs(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return object
    }

    // MARK: - add_reminder

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineReminderToolsE2ETests.responseFormats)
    func `add_reminder schema yields a well-formed tool call`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let tool = MTAddReminderTool().definition
        let prompt = """
        Use the add_reminder tool exactly once to schedule a reminder titled "Buy oat milk" with notes "2 liters from the corner store" and a due date of 2026-05-12T09:00:00Z. Use the default Reminders list (pass an empty list_name) and priority 5. Then stop.
        """

        let response = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [tool],
            ),
        )

        let call = try #require(response.tools.first, "Expected the model to issue a tool call.")
        #expect(call.name == "add_reminder")

        let args = parsedArgs(call.args)
        let title = try #require(args["title"] as? String, "title field missing or not a string")
        #expect(title.localizedCaseInsensitiveContains("oat milk"))
        #expect(args["notes"] as? String != nil)
        #expect(args["due_date"] as? String != nil)
        #expect(args["priority"] as? Int != nil || args["priority"] as? Double != nil)
        #expect(args["list_name"] as? String != nil)
    }

    // MARK: - query_reminders

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineReminderToolsE2ETests.responseFormats)
    func `query_reminders schema yields a well-formed tool call`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let tool = MTQueryReminderTool().definition
        let prompt = """
        Use the query_reminders tool exactly once to list every incomplete reminder in the user's "Inbox" list with no date filters applied. Pass empty strings for all date bounds. Then stop.
        """

        let response = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 256,
                temperature: 0,
                tools: [tool],
            ),
        )

        let call = try #require(response.tools.first, "Expected the model to issue a tool call.")
        #expect(call.name == "query_reminders")

        let args = parsedArgs(call.args)
        let status = try #require(args["status"] as? String)
        #expect(["incomplete", "completed", "all"].contains(status))
        #expect(args["list_name"] as? String != nil)
        for key in [
            "due_start_date", "due_end_date",
            "alert_start_date", "alert_end_date",
            "completed_start_date", "completed_end_date",
        ] {
            #expect(args[key] as? String != nil, "Missing required field \(key)")
        }
    }

    // MARK: - update_reminder (clear flags)

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineReminderToolsE2ETests.responseFormats)
    func `update_reminder schema includes clear flags and round-trips a clear request`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let tool = MTUpdateReminderTool().definition
        let prompt = """
        Call update_reminder exactly once with this JSON intent:
        {
          "reminder_id": "test-reminder-id-1234",
          "title": "",
          "notes": "",
          "due_date": "",
          "list_name": "",
          "priority": -1,
          "clear_notes": true,
          "clear_due_date": false,
          "clear_priority": true
        }
        Emit the tool call and stop.
        """

        let response = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 1024,
                temperature: 0,
                tools: [tool],
            ),
        )

        let call = try #require(response.tools.first, "Expected a tool call from the model.")
        #expect(call.name == "update_reminder")

        let args = parsedArgs(call.args)
        let reminderId = try #require(args["reminder_id"] as? String)
        #expect(reminderId.contains("1234"))

        // The required-list in strict schema must produce all clear_* keys.
        for key in ["clear_notes", "clear_due_date", "clear_priority"] {
            #expect(args[key] as? Bool != nil, "Missing required boolean field \(key)")
        }
        let clearNotes = (args["clear_notes"] as? Bool) ?? false
        let clearPriority = (args["clear_priority"] as? Bool) ?? false
        #expect(clearNotes, "Model should set clear_notes=true given the prompt")
        #expect(clearPriority, "Model should set clear_priority=true given the prompt")

        // Sanity: parseChanges accepts whatever the model produced.
        var enriched = args
        enriched["reminder_id"] = reminderId
        let normalized = normalize(args: enriched)
        _ = try MTUpdateReminderTool.parseChanges(from: normalized)
    }

    // MARK: - delete_reminder

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineReminderToolsE2ETests.responseFormats)
    func `delete_reminder schema yields a well-formed tool call`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let tool = MTDeleteReminderTool().definition
        let prompt = """
        The user already ran query_reminders. Use the delete_reminder tool exactly once to delete the reminder whose id is "test-reminder-id-DELETE". Then stop.
        """

        let response = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 128,
                temperature: 0,
                tools: [tool],
            ),
        )

        let call = try #require(response.tools.first, "Expected a tool call from the model.")
        #expect(call.name == "delete_reminder")
        let args = parsedArgs(call.args)
        let id = try #require(args["reminder_id"] as? String)
        #expect(id.contains("DELETE"))
    }

    // MARK: - complete_reminder

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineReminderToolsE2ETests.responseFormats)
    func `complete_reminder schema yields a well-formed tool call`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))

        let client = try makeClient(for: responseFormat)
        let tool = MTCompleteReminderTool().definition
        let prompt = """
        The user already ran query_reminders. Use the complete_reminder tool exactly once to mark the reminder whose id is "test-reminder-id-COMPLETE" as done. Then stop.
        """

        let response = try await collect(
            client,
            body: ChatRequestBody(
                messages: [.user(content: .text(prompt))],
                maxCompletionTokens: 128,
                temperature: 0,
                tools: [tool],
            ),
        )

        let call = try #require(response.tools.first, "Expected a tool call from the model.")
        #expect(call.name == "complete_reminder")
        let args = parsedArgs(call.args)
        let id = try #require(args["reminder_id"] as? String)
        #expect(id.contains("COMPLETE"))
        let completed = try #require(args["completed"] as? Bool)
        #expect(completed)
    }

    // MARK: - Helpers

    /// JSON deserialization of integer fields can land as either `Int` or
    /// `NSNumber` depending on the parser path. `parseChanges` reads them as
    /// `Int`, so promote known-numeric fields if the model returned a non-Int
    /// numeric type (e.g. `Double` for "5.0").
    private func normalize(args: [String: Any]) -> [String: Any] {
        var result = args
        if let priority = result["priority"] as? Double {
            result["priority"] = Int(priority)
        }
        if result["priority"] == nil {
            result["priority"] = -1
        }
        for key in ["title", "notes", "due_date", "list_name"] {
            if result[key] == nil {
                result[key] = ""
            }
        }
        for key in ["clear_notes", "clear_due_date", "clear_priority"] {
            if result[key] == nil {
                result[key] = false
            }
        }
        return result
    }
}

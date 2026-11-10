//
//  ToolArgumentLabelTests.swift
//  FlowDownUnitTests
//

@testable import ChatClientKit
@testable import FlowDown
import Foundation
import MCP
import Testing
import UIKit

@Suite(.serialized)
struct ToolArgumentLabelTests {
    @Test(arguments: [
        ("end_date", "End date"),
        ("include_all_day_events", "Include all day events"),
        ("startDate", "Start date"),
        ("repoName", "Repo name"),
        ("start-date", "Start date"),
        ("max-results", "Max results"),
        ("repoURL", "Repo URL"),
        ("URLString", "URL string"),
        ("MAX_RESULTS", "Max results"),
        ("__leading_trailing__", "Leading trailing"),
        ("question", "Question"),
        ("page2Size", "Page2 size"),
        ("", ""),
        ("__", "__"),
    ])
    func `a key reads as words with the first letter capitalised`(row: (key: String, label: String)) {
        #expect(ToolArgumentLabel.words(of: row.key) == row.label)
    }

    @Test(arguments: ["repoName", "question", "max-results", "user_id"])
    func `a key without a label falls back to words`(key: String) {
        #expect(ToolArgumentLabel.known(key) == nil)
        #expect(ToolArgumentLabel.text(for: key) == ToolArgumentLabel.words(of: key))
        #expect(ToolArgumentLabel.text(for: key) != key)
    }

    @Test
    func `a built-in tool's key reads as its label in the app's language`() throws {
        #expect(ToolArgumentLabel.text(for: "start_date") == String(localized: "Start Date"))
        #expect(ToolArgumentLabel.text(for: "end_date") == String(localized: "End Date"))

        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try #require(Bundle(path: path))
        #expect(ToolArgumentLabel.text(for: "start_date", bundle: chinese) == "开始日期")
        #expect(ToolArgumentLabel.text(for: "end_date", bundle: chinese) == "结束日期")
        #expect(ToolArgumentLabel.text(for: "include_all_day_events", bundle: chinese) == "包括全天事件")
        // No label: words, in any language.
        #expect(ToolArgumentLabel.text(for: "repoName", bundle: chinese) == "Repo name")
    }

    static let gatedTools: [any ModelTool] = [
        MTAddCalendarTool(),
        MTQueryCalendarTool(),
        MTAddReminderTool(),
        MTQueryReminderTool(),
        MTUpdateReminderTool(),
        MTCompleteReminderTool(),
        MTDeleteReminderTool(),
        MTLocationTool(),
    ]

    @Test
    func `every argument of a built-in tool that asks first has a label`() {
        for tool in Self.gatedTools {
            #expect(tool.access == .privateData)
            guard case let .function(name, _, parameters, _) = tool.definition,
                  case let .object(properties)? = parameters?["properties"]
            else {
                Issue.record("\(tool.functionName) declares no properties")
                continue
            }
            for key in properties.keys {
                #expect(ToolArgumentLabel.known(key) != nil, "\(name): \(key)")
            }
        }
    }

    @MainActor
    @Test
    func `the card names arguments by label and keeps their values`() {
        let host = EditorHost()
        host.editor.showToolApproval(Self.request(arguments: #"{"end_date":"2026-11-12","filter":{"tag":"work"},"repoName":"FlowDown","start_date":"2026-11-10"}"#))
        host.layout()

        let texts = Self.labelTexts(in: host.editor.toolApproval)
        #expect(texts.contains(String(localized: "Start Date")))
        #expect(texts.contains(String(localized: "End Date")))
        #expect(texts.contains("Repo name"))
        #expect(texts.contains("Filter"))
        #expect(texts.contains("2026-11-10"))
        #expect(texts.contains("2026-11-12"))
        #expect(texts.contains(#"{"tag":"work"}"#))
        #expect(texts.contains("FlowDown"))
        for key in ["start_date", "end_date", "repoName", "filter"] {
            #expect(!texts.contains(key))
        }
    }

    @Test(arguments: [
        (#"{"start_date":"a","end_date":"b"}"#, ["start_date", "end_date"]),
        (#" { "z" : 1 , "a" : [1, {"q": "}"}], "m": {"x": [true]}, "k\"ey": "\\", "b": null } "#, ["z", "a", "m", #"k"ey"#, "b"]),
        (#"{"\u0061b":false,"c":"x,y"}"#, ["ab", "c"]),
        (#"{"a":1,"a":2}"#, ["a"]),
        ("{}", []),
        ("", []),
        ("[1,2]", []),
        (#"{"a":1"#, []),
        (#"{"a" 1}"#, []),
        ("not json", []),
    ])
    func `the model's key order is read off the JSON it sent`(row: (json: String, keys: [String])) {
        #expect(ModelToolArgumentOrder.keys(in: row.json) == row.keys)
    }

    @Test
    func `the schema's order comes first, then the model's`() {
        #expect(ModelToolArgumentOrder.order(schema: ["start_date", "end_date"], arguments: #"{"x":1,"end_date":2,"start_date":3,"b":4}"#)
            == ["start_date", "end_date", "x", "b"])
        #expect(ModelToolArgumentOrder.order(schema: [], arguments: #"{"zeta":1,"alpha":2}"#) == ["zeta", "alpha"])
        #expect(ModelToolArgumentOrder.order(schema: ["a"], arguments: "oops") == ["a"])
    }

    @Test
    func `a built-in tool orders its arguments as its schema declares them`() {
        #expect(MTQueryCalendarTool().argumentOrder == ["start_date", "end_date", "include_all_day_events"])
        #expect(MTAddReminderTool().argumentOrder == ["title", "notes", "due_date", "priority", "list_name"])
        #expect(MTUpdateReminderTool().argumentOrder.prefix(4) == ["reminder_id", "title", "notes", "clear_notes"])
        for tool in Self.gatedTools {
            guard case let .function(name, _, parameters, _) = tool.definition,
                  case let .object(properties)? = parameters?["properties"]
            else { continue }
            #expect(Set(tool.argumentOrder) == Set(properties.keys), "\(name)")
            #expect(tool.argumentOrder.count == properties.count, "\(name)")
        }
    }

    @Test
    func `an MCP tool leaves the order to the model`() async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let tool = MCPTool(
            toolInfo: MCPToolInfo(
                name: "search",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "query": .object(["type": .string("string")]),
                        "limit": .object(["type": .string("integer")]),
                    ]),
                    "required": .array([.string("query")]),
                ]),
                serverID: "order-server",
                serverName: "order.example.com",
            ),
            mcpService: .shared,
        )
        // The strict schema lists every property, sorted, which is not the server's order.
        #expect(tool.argumentOrder.isEmpty)

        let call = try #require(ModelToolSet(tools: [tool]).resolve(ToolRequest(name: "search", args: #"{"query":"swift","limit":null,"reason":"why"}"#)))
        #expect(call.argumentOrder == ["query", "limit", "reason"])
    }

    @Test
    func `a resolved call carries the schema's order, whatever order the model used`() throws {
        let toolSet = ModelToolSet(tools: [MTQueryCalendarTool()])
        let call = try #require(toolSet.resolve(ToolRequest(
            name: "query_calendar_events",
            args: #"{"reason":"Check","include_all_day_events":true,"end_date":"2026-11-12","start_date":"2026-11-10"}"#,
        )))
        #expect(call.argumentOrder == ["start_date", "end_date", "include_all_day_events", "reason"])
        #expect(call.reason == "Check")
    }

    @Test
    func `rows follow the order, then the rest by name`() {
        let rows = ToolArgumentLabel.rows(
            of: #"{"b_extra":"2","a_extra":"1","end_date":"E","start_date":"S","empty":""}"#,
            order: ["start_date", "end_date"],
            title: "Query Calendar",
        )
        #expect(rows.map(\.label) == [String(localized: "Start Date"), String(localized: "End Date"), "A extra", "B extra"])
        #expect(rows.map(\.value) == ["S", "E", "1", "2"])
        #expect(ToolArgumentLabel.rows(of: "", order: [], title: "T").isEmpty)
        #expect(ToolArgumentLabel.rows(of: "{}", order: [], title: "T").isEmpty)
        #expect(ToolArgumentLabel.rows(of: "oops", order: [], title: "T") == [.init(label: nil, value: "oops")])
        #expect(ToolArgumentLabel.rows(of: #"{"reason":"T","q":"x"}"#, order: [], title: "T").map(\.value) == ["x"])
    }

    @Test
    func `only a JSON boolean reads Yes or No`() throws {
        let rows = ToolArgumentLabel.rows(
            of: #"{"on":true,"off":false,"text":"true","one":1,"zero":0,"nested":{"flag":true},"list":[false]}"#,
            order: ["on", "off", "text", "one", "zero", "nested", "list"],
            title: "Tool",
        )
        #expect(rows.map(\.value) == [
            String(localized: "Yes"), String(localized: "No"), "true", "1", "0", #"{"flag":true}"#, "[false]",
        ])
        #expect(String(localized: "Yes") == "Yes")
        #expect(String(localized: "No") == "No")

        let path = try #require(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try #require(Bundle(path: path))
        #expect(ToolArgumentLabel.value(true, bundle: chinese) == "是")
        #expect(ToolArgumentLabel.value(false, bundle: chinese) == "否")
        #expect(ToolArgumentLabel.value(1, bundle: chinese) == "1")
    }

    @MainActor
    @Test
    func `the card lists arguments in the schema's order with booleans as Yes or No`() throws {
        let host = EditorHost()
        var request = Self.request(arguments: #"{"end_date":"2026-11-12","include_all_day_events":true,"start_date":"2026-11-10"}"#)
        request.argumentOrder = MTQueryCalendarTool().argumentOrder
        host.editor.showToolApproval(request)
        host.layout()

        let texts = Self.labelTexts(in: host.editor.toolApproval)
        let start = try #require(texts.firstIndex(of: String(localized: "Start Date")))
        let end = try #require(texts.firstIndex(of: String(localized: "End Date")))
        let allDay = try #require(texts.firstIndex(of: String(localized: "Include All-Day Events")))
        #expect(start < end && end < allDay)
        #expect(texts[allDay + 1] == String(localized: "Yes"))
        #expect(!texts.contains("true"))
    }

    @MainActor
    @Test
    func `a call without arguments shows no argument names`() {
        let host = EditorHost()
        host.editor.showToolApproval(Self.request(arguments: "{}"))
        host.layout()

        let texts = Self.labelTexts(in: host.editor.toolApproval)
        #expect(host.editor.toolApproval.isPresenting)
        #expect(texts == ["Query Calendar"])
    }

    static func request(arguments: String) -> ModelToolApprovalRequest {
        ModelToolApprovalRequest(
            id: UUID(),
            toolName: "Query Calendar",
            icon: "calendar",
            source: nil,
            reason: nil,
            summary: nil,
            arguments: arguments,
        )
    }

    /// The text of every label in `view`, outside the buttons.
    @MainActor
    static func labelTexts(in view: UIView) -> [String] {
        view.subviews.flatMap { subview -> [String] in
            if subview is UIButton { return [] }
            if let label = subview as? UILabel, !label.isHidden, let text = label.text {
                return [text]
            }
            return labelTexts(in: subview)
        }
    }
}

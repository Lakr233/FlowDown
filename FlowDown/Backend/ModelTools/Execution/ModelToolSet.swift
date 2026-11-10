//
//  ModelToolSet.swift
//  FlowDown
//

import ChatClientKit
import Foundation

/// The tools one inference offers, fixed when its request is built. Calls
/// resolve against what the model was given, not against whatever is
/// enabled by the time they arrive.
struct ModelToolSet: @unchecked Sendable {
    /// A call matched to its tool.
    struct Call {
        let tool: any ModelTool
        let arguments: ModelToolArguments
        /// The reason the call gave, nil when it gave none.
        let reason: String?
        /// The order to show the arguments in: the tool's, then the model's.
        let argumentOrder: [String]
    }

    private struct Entry {
        let tool: any ModelTool
        /// The definition the model was given.
        let definition: ChatRequestBody.Tool
        /// FlowDown added `reason` to it, so calls carry one to take off.
        let carriesReason: Bool
    }

    private let entries: [Entry]

    static let empty = ModelToolSet(tools: [])

    init(tools: [any ModelTool]) {
        entries = tools.map { tool in
            let added = ModelToolReason.adding(to: tool.definition)
            return Entry(tool: tool, definition: added ?? tool.definition, carriesReason: added != nil)
        }
    }

    var isEmpty: Bool {
        entries.isEmpty
    }

    /// The definitions to send, nil when there is nothing to offer.
    var definitions: [ChatRequestBody.Tool]? {
        entries.isEmpty ? nil : entries.map(\.definition)
    }

    func contains(where predicate: (any ModelTool) -> Bool) -> Bool {
        entries.contains { predicate($0.tool) }
    }

    /// The definition the model was given for `name`.
    func definition(named name: String) -> ChatRequestBody.Tool? {
        entry(named: name)?.definition
    }

    /// The call's tool and the arguments it reads, nil when no offered tool
    /// has the call's name.
    func resolve(_ request: ToolRequest) -> Call? {
        guard let entry = entry(named: request.name) else { return nil }
        let split = entry.carriesReason ? ModelToolReason.split(request.args) : (arguments: request.args, reason: nil)
        return Call(
            tool: entry.tool,
            arguments: .init(json: split.arguments),
            reason: split.reason,
            argumentOrder: ModelToolArgumentOrder.order(schema: entry.tool.argumentOrder, arguments: request.args),
        )
    }

    /// An exact match first; models sometimes change the case of a name.
    private func entry(named name: String) -> Entry? {
        entries.first { $0.tool.functionName == name }
            ?? entries.first { $0.tool.functionName.lowercased() == name.lowercased() }
    }
}

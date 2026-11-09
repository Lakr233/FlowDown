//
//  ModelTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import Storage
import UIKit

/// What a tool reaches. While Require Confirmation is on, a call to a tool
/// that reaches the user's private data or an MCP server waits for the
/// user; any other call runs at once.
enum ModelToolAccess: Sendable, Equatable {
    /// The web, or data the app keeps itself, such as memories.
    case general
    /// Data the system guards for the user: calendar, reminders, location.
    case privateData
    /// A tool from an MCP server, which reaches whatever the server does.
    case external
}

/// Built-in tools that the settings and the tools menu switch together.
enum ModelToolGroup: Sendable, Equatable {
    case calendar
    case reminders
    case memory
}

/// A function the model can call. A tool only reads its arguments and does
/// its work: asking the user, showing the call and reporting the result to
/// the model belong to the conversation that runs it.
protocol ModelTool: AnyObject, Sendable {
    /// The function as the tool declares it, before FlowDown adds `reason`.
    var definition: ChatRequestBody.Tool { get }
    var interfaceName: String { get }
    var interfaceIcon: String { get }
    var access: ModelToolAccess { get }
    /// The kind of row a call leaves in the conversation.
    var transcriptRole: Message.Role { get }

    /// What the approval card says the call will do, in the user's words,
    /// such as the event it adds. Nil shows the arguments by name.
    func approvalSummary(for arguments: ModelToolArguments) async -> String?

    func execute(
        _ arguments: ModelToolArguments,
        context: ModelToolContext,
    ) async throws -> ModelToolOutput
}

extension ModelTool {
    var functionName: String {
        switch definition {
        case let .function(name, _, _, _): name
        }
    }

    var access: ModelToolAccess {
        .general
    }

    var transcriptRole: Message.Role {
        .toolHint
    }

    func approvalSummary(for _: ModelToolArguments) async -> String? {
        nil
    }
}

/// A built-in tool, switched on and off in settings by its control object.
protocol ConfigurableModelTool: ModelTool {
    static var controlObject: ConfigurableObject { get }
    var group: ModelToolGroup? { get }
}

extension ConfigurableModelTool {
    var group: ModelToolGroup? {
        nil
    }

    var interfaceIcon: String {
        Self.controlObject.icon
    }

    var isEnabled: Bool {
        get { ConfigurableKit.value(forKey: Self.controlObject.key) ?? true }
        set { ConfigurableKit.set(value: newValue, forKey: Self.controlObject.key) }
    }

    func createConfigurableObjectView() -> UIView {
        MainActor.assumeIsolated {
            Self.controlObject.createView()
        }
    }
}

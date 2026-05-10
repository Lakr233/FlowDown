//
//  ModelToolsManager.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/27/25.
//

import AlertController
import AVFoundation
import ChatClientKit
import ConfigurableKit
import Foundation
import MCP
import UIKit

class ModelToolsManager {
    static let shared = ModelToolsManager()

    let tools: [ModelTool]

    static let skipConfirmationKey = "ModelToolsManager.skipConfirmation"
    static var skipConfirmationValue: Bool {
        get { UserDefaults.standard.bool(forKey: ModelToolsManager.skipConfirmationKey) }
        set { UserDefaults.standard.set(newValue, forKey: ModelToolsManager.skipConfirmationKey) }
    }

    static var skipConfirmation: ConfigurableToggleActionView {
        .init().with {
            $0.actionBlock = { skipConfirmationValue = $0 }
            $0.configure(icon: UIImage(systemName: "hammer"))
            $0.configure(title: "Skip Tool Confirmation")
            $0.configure(description: "Skip the confirmation dialog when executing tools.")
            $0.boolValue = skipConfirmationValue
        }
    }

    private init() {
        #if targetEnvironment(macCatalyst)
            tools = [
                MTAddCalendarTool(),
                MTQueryCalendarTool(),

                MTAddReminderTool(),
                MTQueryReminderTool(),
                MTUpdateReminderTool(),
                MTCompleteReminderTool(),
                MTDeleteReminderTool(),

                MTWebScraperTool(),
                MTWebSearchTool(),

                //            MTLocationTool(),

                MTURLTool(),

                MTStoreMemoryTool(),
                MTRecallMemoryTool(),
                MTListMemoriesTool(),
                MTUpdateMemoryTool(),
                MTDeleteMemoryTool(),
            ]
        #else
            tools = [
                MTAddCalendarTool(),
                MTQueryCalendarTool(),

                MTAddReminderTool(),
                MTQueryReminderTool(),
                MTUpdateReminderTool(),
                MTCompleteReminderTool(),
                MTDeleteReminderTool(),

                MTWebScraperTool(),
                MTWebSearchTool(),

                MTLocationTool(),

                MTURLTool(),

                MTStoreMemoryTool(),
                MTRecallMemoryTool(),
                MTListMemoriesTool(),
                MTUpdateMemoryTool(),
                MTDeleteMemoryTool(),
            ]
        #endif

        #if DEBUG
            var registeredToolNames: Set<String> = []
        #endif

        for tool in tools {
            Logger.model.debugFile("registering tool: \(tool.functionName)")
            #if DEBUG
                assert(registeredToolNames.insert(tool.functionName).inserted)
            #endif
        }
    }

    var enabledTools: [ModelTool] {
        tools.filter { tool in
            if tool is MTWebSearchTool { return true }
            return tool.isEnabled
        }
    }

    var memoryTools: [ModelTool] {
        tools.filter(Self.isMemoryTool)
    }

    var enabledMemoryTools: [ModelTool] {
        enabledTools.filter(Self.isMemoryTool)
    }

    var enabledMemoryWritingTools: [ModelTool] {
        enabledTools.filter(Self.isMemoryWritingTool)
    }

    var canStoreMemory: Bool {
        enabledTools.contains { $0 is MTStoreMemoryTool }
    }

    static func isMemoryTool(_ tool: ModelTool) -> Bool {
        tool is MTStoreMemoryTool ||
            tool is MTRecallMemoryTool ||
            tool is MTListMemoriesTool ||
            tool is MTUpdateMemoryTool ||
            tool is MTDeleteMemoryTool
    }

    static func isMemoryWritingTool(_ tool: ModelTool) -> Bool {
        tool is MTStoreMemoryTool ||
            tool is MTUpdateMemoryTool ||
            tool is MTDeleteMemoryTool
    }

    static func shouldExposeMemory(
        modelWillExecuteTools: Bool,
        enabledTools: [ModelTool],
    ) -> Bool {
        guard modelWillExecuteTools else { return false }
        return enabledTools.contains(where: isMemoryTool)
    }

    func getEnabledToolsIncludeMCP() async -> [ModelTool] {
        var result = enabledTools
        let mcpTools = await MCPService.shared.listServerTools()
        result.append(contentsOf: mcpTools.filter(\.isEnabled))
        return result
    }

    var configurableTools: [ModelTool] {
        tools.filter { tool in
            if tool is MTWebSearchTool { return false }
            if tool is MTStoreMemoryTool { return false }
            if tool is MTRecallMemoryTool { return false }
            if tool is MTListMemoriesTool { return false }
            if tool is MTUpdateMemoryTool { return false }
            if tool is MTDeleteMemoryTool { return false }
            if tool is MTCompleteReminderTool { return false }
            return true
        }
    }

    func tool(for request: ToolRequest) -> ModelTool? {
        Logger.model.debugFile("finding tool call with function name \(request.name)")
        return enabledTools.first {
            $0.functionName.lowercased() == request.name.lowercased()
        }
    }

    func findTool(for request: ToolRequest) async -> ModelTool? {
        Logger.model.debugFile("finding tool call with function name \(request.name)")
        let allTools = await getEnabledToolsIncludeMCP()
        return allTools.first {
            $0.functionName.lowercased() == request.name.lowercased()
        }
    }

    struct ToolResultContents: Equatable, Hashable, Codable {
        let text: String

        struct Attachment: Equatable, Hashable, Codable {
            let name: String
            let data: Data
            let mimeType: String?
        }

        let imageAttachments: [Attachment]
        let audioAttachments: [Attachment]
    }

    func perform(withTool tool: ModelTool, parms: String, anchorTo view: UIView) async throws -> ToolResultContents {
        if Self.skipConfirmationValue {
            let ans = try await tool.execute(with: parms, anchorTo: view)
            return processToolResult(ans)
        } else {
            return try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                    let setupContext: (ActionContext) -> Void = { context in
                        context.addAction(title: "Cancel") {
                            context.dispose {
                                let error = NSError(
                                    domain: "ToolCall",
                                    code: 500,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: String(localized: "Tool execution cancelled by user"),
                                    ],
                                )
                                continuation.resume(throwing: error)
                            }
                        }
                        context.addAction(title: "Use Tool", attribute: .accent) {
                            context.dispose {
                                Task.detached(priority: .userInitiated) {
                                    do {
                                        let ans = try await tool.execute(with: parms, anchorTo: view)
                                        let result = self.processToolResult(ans)
                                        continuation.resume(returning: result)
                                    } catch {
                                        let error = NSError(
                                            domain: "ToolCall",
                                            code: 500,
                                            userInfo: [
                                                NSLocalizedDescriptionKey: String(localized: "Tool execution failed: \(error.localizedDescription)"),
                                            ],
                                        )
                                        continuation.resume(throwing: error)
                                    }
                                }
                            }
                        }
                    }

                    let alert = if let tool = tool as? MCPTool {
                        AlertViewController(
                            title: "Execute MCP Tool",
                            message: "The model wants to execute '\(tool.toolInfo.name)' from \(tool.toolInfo.serverName). This tool can access external resources.\n\nDescription: \(tool.toolInfo.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No description available")",
                            setupActions: setupContext,
                        )
                    } else {
                        AlertViewController(
                            title: "Tool Call",
                            message: "Your model is calling a tool: \(tool.interfaceName)",
                            setupActions: setupContext,
                        )
                    }

                    // Check if view controller already has a presented view controller
                    guard let parentVC = view.parentViewController else {
                        let error = NSError(
                            domain: "ToolCall",
                            code: 500,
                            userInfo: [
                                NSLocalizedDescriptionKey: String(localized: "Tool execution failed: parent view controller not found."),
                            ],
                        )
                        continuation.resume(throwing: error)
                        return
                    }

                    guard parentVC.presentedViewController == nil else {
                        let error = NSError(
                            domain: "ToolCall",
                            code: 500,
                            userInfo: [
                                NSLocalizedDescriptionKey: String(localized: "Tool execution failed: authorization dialog is already presented."),
                            ],
                        )
                        continuation.resume(throwing: error)
                        return
                    }

                    parentVC.present(alert, animated: true)
                }
            }
        }
    }

    private func processToolResult(_ ans: String) -> ToolResultContents {
        if let value = try? [Tool.Content].decodeContents(ans) {
            var textContent: [String] = []
            var imageAttachments: [ToolResultContents.Attachment] = []
            var audioAttachments: [ToolResultContents.Attachment] = []
            for content in value {
                switch content {
                case let .text(text: string, annotations: _, _meta: _):
                    textContent.append(string)
                case let .image(
                    data: dataString,
                    mimeType: mimeType,
                    annotations: _,
                    _meta: metadata,
                ):
                    var name = metadata?["name"] as? String ?? ""
                    if name.isEmpty {
                        name = String(localized: "Tool Provided Image")
                        name += " " + mimeType
                    }
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = parseDataFromString(dataString), UIImage(data: data) != nil {
                        imageAttachments.append(.init(
                            name: name,
                            data: data,
                            mimeType: mimeType.nilIfEmpty,
                        ))
                    } else {
                        Logger.model.errorFile("failed to parse image data from string")
                    }
                case let .audio(
                    data: dataString,
                    mimeType: mimeType,
                    annotations: _,
                    _meta: _,
                ):
                    var name = String(localized: "Tool Provided Audio")
                    if !mimeType.isEmpty {
                        name += " " + mimeType
                    }
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    if let data = parseDataFromString(dataString) {
                        audioAttachments.append(.init(
                            name: name,
                            data: data,
                            mimeType: mimeType.nilIfEmpty,
                        ))
                    } else {
                        Logger.model.errorFile("failed to parse audio data from string")
                    }
                case let .resource(resource, annotations: _, _meta: _):
                    let textValue = resource.text ?? resource.blob ?? ""
                    let mimeTypeValue = resource.mimeType ?? ""
                    textContent.append("[\(textValue) \(mimeTypeValue)](\(resource.uri))")
                case let .resourceLink(
                    uri: uri,
                    name: name,
                    title: title,
                    description: description,
                    mimeType: mimeType,
                    annotations: annotations,
                ):
                    let annotationsValue: String = if let annotations {
                        {
                            let data = try? JSONEncoder().encode(annotations)
                            let value = String(data: data ?? .init(), encoding: .utf8)
                            return value ?? ""
                        }()
                    } else {
                        ""
                    }
                    let titleValue = if let title { String(describing: title) } else { "" }
                    let value = """
                    [\(titleValue) \(name) \(mimeType ?? "application/resources")](\(uri))
                    \(description ?? "")
                    Annotations: \(annotationsValue)
                    """
                    textContent.append(value)
                }
            }
            return .init(
                text: textContent.joined(separator: "\n"),
                imageAttachments: imageAttachments,
                audioAttachments: audioAttachments,
            )
        } else {
            return .init(text: ans, imageAttachments: [], audioAttachments: [])
        }
    }

    private func parseDataFromString(_ dataString: String) -> Data? {
        AttachmentDataParser.decodeData(from: dataString)
    }
}

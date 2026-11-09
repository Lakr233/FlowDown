//
//  ConversationSession+ToolCalls.swift
//  FlowDown
//

import ChatClientKit
import Foundation
import Storage
import UniformTypeIdentifiers

extension ConversationSession {
    /// What one call left for the model: its result, and attachment turns
    /// that may only follow every result of the assistant turn.
    private struct ToolCallOutcome {
        var result: String
        var attachmentMessages: [ChatRequestBody.Message] = []
    }

    /// Runs the calls an assistant turn asked for, one at a time in the order
    /// it asked, and appends a result for each. A call the user turns down,
    /// a tool that fails and a name no tool answers to all become results
    /// the model reads; only cancelling the turn ends it.
    func performToolCalls(
        _ requests: [ToolRequest],
        toolSet: ModelToolSet,
        modelID: ModelManager.ModelIdentifier,
        requestMessages: inout [ChatRequestBody.Message],
    ) async throws {
        showActivity(String(localized: "Utilizing tool call"))

        // Tool results must directly follow the assistant turn that requested
        // them, so attachment messages join the request after every result.
        var deferredAttachmentMessages: [ChatRequestBody.Message] = []
        for request in requests {
            try checkCancellation()
            let outcome = try await performToolCall(request, toolSet: toolSet, modelID: modelID)
            requestMessages.append(.tool(content: .text(outcome.result), toolCallID: request.id))
            deferredAttachmentMessages.append(contentsOf: outcome.attachmentMessages)
        }
        requestMessages.append(contentsOf: deferredAttachmentMessages)
        await requestUpdate()
    }

    private func performToolCall(
        _ request: ToolRequest,
        toolSet: ModelToolSet,
        modelID: ModelManager.ModelIdentifier,
    ) async throws -> ToolCallOutcome {
        guard let call = toolSet.resolve(request) else {
            Logger.chatService.errorFile("unable to find tool for request: \(request.name)")
            let row = appendNewMessage(role: .toolHint)
            encodeToolRequestAndAttachToToolMessage(request, message: row)
            row.update(\.toolStatus, to: .init(
                name: request.name,
                state: ToolCallState.failed,
                message: String(localized: "Unable to process tool request with name: \(request.name)"),
            ))
            await requestUpdate()
            return .init(result: "No tool named \(request.name) is available. Call one of the provided tools instead.")
        }

        let tool = call.tool
        showActivity(String(localized: "Utilizing tool: \(tool.interfaceName)"))
        let row = appendNewMessage(role: tool.transcriptRole)
        encodeToolRequestAndAttachToToolMessage(request, message: row)
        if row.role == .toolHint {
            row.update(\.toolStatus, to: .init(name: tool.interfaceName, state: ToolCallState.running, message: ""))
        }
        await requestUpdate()
        // The running row, and the approval card when the call asks, are the
        // visible progress now.
        hideActivity()

        do {
            if ModelToolAuthorization.needsApproval(tool) {
                try await requestApproval(for: call)
            }
            let output = try await tool.execute(call.arguments, context: .init(session: self, row: row))
            return await settle(row, of: tool, with: output, modelID: modelID)
        } catch is ModelToolDenial {
            settle(row, state: ToolCallState.failed, message: String(localized: "Tool call denied."))
            await requestUpdate()
            return .init(result: "The user denied this call. Do not retry it unless the user asks you to.")
        } catch {
            let cancelled = error is CancellationError
                || error is InferenceUserCancellationError
                || Task.isCancelled
            // A search cut off by cancelling reads as interrupted, not failed.
            if !(cancelled && row.role == .webSearch) {
                settle(
                    row,
                    state: ToolCallState.failed,
                    message: cancelled ? String(localized: "Cancelled by user.") : error.localizedDescription,
                )
            }
            save()
            await requestUpdate()
            // The row is settled; only then may cancellation abort the round,
            // otherwise it would stay "running" forever.
            if cancelled { throw InferenceUserCancellationError() }
            return .init(result: "Tool execution failed. Reason: \(error.localizedDescription)")
        }
    }

    /// Shows the call's approval card and waits. Throws `ModelToolDenial`
    /// when the user turns it down, or the cancellation when the turn ends
    /// while it waits.
    private func requestApproval(for call: ModelToolSet.Call) async throws {
        let tool = call.tool
        let request = await ModelToolApprovalRequest(
            id: UUID(),
            toolName: tool.interfaceName,
            icon: tool.interfaceIcon,
            source: (tool as? MCPTool).flatMap { MCPService.shared.server(with: $0.toolInfo.serverID)?.displayName },
            reason: call.reason,
            summary: tool.approvalSummary(for: call.arguments),
            arguments: call.arguments.json,
        )
        let decision = await toolApprovalGate.request(request)
        try checkCancellation()
        guard decision == .approve else { throw ModelToolDenial() }
    }

    /// Records a finished call on its row and turns its output into what the
    /// model reads. Images and audio become an attachment row, and reach the
    /// model as attachments after every result of the turn.
    private func settle(
        _ row: Message,
        of tool: any ModelTool,
        with output: ModelToolOutput,
        modelID: ModelManager.ModelIdentifier,
    ) async -> ToolCallOutcome {
        var text = output.text
        var attachmentMessages: [ChatRequestBody.Message] = []
        if !output.images.isEmpty || !output.audio.isEmpty {
            let attachments = await collectAttachments(of: output, from: tool)
            text = [output.text, attachments.summary]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .joined(separator: "\n")
            // Visual models get the images in the request; for other models the
            // tool has usually returned the text they need already.
            let modelCapabilities = ModelManager.shared.modelCapabilities(identifier: modelID)
            attachmentMessages = await makeMessageFromAttachments(
                attachments.objects,
                modelCapabilities: modelCapabilities,
            )
        }
        let reported = ModelToolOutput(text: text)
        settle(row, state: ToolCallState.succeeded, message: reported.truncatedText)
        await requestUpdate()
        // Search results are pages the context trimming already accounts
        // for; cutting them would leave a page half read.
        let result = row.role == .webSearch ? text : reported.modelText
        return .init(result: result, attachmentMessages: attachmentMessages)
    }

    private func settle(_ row: Message, state: Int, message: String) {
        switch row.role {
        case .toolHint:
            var status = row.toolStatus
            status.state = state
            status.message = message
            row.update(\.toolStatus, to: status)
        case .webSearch:
            // The search keeps its own progress; a failure marks it failed.
            guard state == ToolCallState.failed else { return }
            var status = row.webSearchStatus
            if status.proccessProgress >= 0, status.proccessProgress < 1 {
                status.proccessProgress = -1
                row.assign(\.webSearchStatus, to: status)
            }
        default:
            assertionFailure("unexpected tool row role \(row.role)")
        }
    }

    /// Holds the output's images and audio on a user row of their own.
    private func collectAttachments(
        of output: ModelToolOutput,
        from tool: any ModelTool,
    ) async -> (objects: [RichEditorView.Object.Attachment], summary: String) {
        let collectorMessage = appendNewMessage(role: .user)
        markAsAttachmentHolder(collectorMessage)

        var objects: [RichEditorView.Object.Attachment] = output.images.map { image in
            RichEditorView.Object.Attachment(
                type: .image,
                name: String(localized: "Tool Provided Image"),
                previewImage: image.data,
                imageRepresentation: image.data,
                textRepresentation: "",
                storageSuffix: UUID().uuidString,
            )
        }

        for (index, audio) in output.audio.enumerated() {
            showActivity(String(localized: "Transcoding audio attachment \(index + 1)"))
            do {
                let fileExtension = audio.mimeType.flatMap { mime in
                    UTType(mimeType: mime)?.preferredFilenameExtension
                }
                let transcoded = try await AudioTranscoder.transcode(
                    data: audio.data,
                    fileExtension: fileExtension,
                )
                let attachment = try await RichEditorView.Object.Attachment.makeAudioAttachment(
                    transcoded: transcoded,
                    storage: nil,
                    suggestedName: audio.name,
                )
                objects.append(attachment)
            } catch {
                Logger.model.errorFile(
                    "failed to process audio attachment from tool \(tool.interfaceName): \(error.localizedDescription)",
                )
            }
        }

        let count = objects.count
        collectorMessage.update(\.document, to: String(
            localized: "Collected \(count) attachments from tool \(tool.interfaceName).",
        ))
        addAttachments(objects, to: collectorMessage)
        updateAttachments(objects, for: collectorMessage)
        await requestUpdate()
        return (objects, collectorMessage.document)
    }
}

/// The states a tool row's `ToolStatus.state` stores.
enum ToolCallState {
    static let running = 0
    static let succeeded = 1
    static let failed = 2
}

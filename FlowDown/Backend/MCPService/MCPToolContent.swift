//
//  MCPToolContent.swift
//  FlowDown
//

import Foundation
import MCP
import UIKit

/// Turns what an MCP tool returned into a tool output: text and resources
/// as text, images and audio as attachments the model sees after the turn.
enum MCPToolContent {
    static func output(from contents: [Tool.Content]) -> ModelToolOutput {
        var textContent: [String] = []
        var images: [ModelToolOutput.Attachment] = []
        var audio: [ModelToolOutput.Attachment] = []
        for content in contents {
            switch content {
            case let .text(text: string, annotations: _, _meta: _):
                textContent.append(string)
            case let .image(data: dataString, mimeType: mimeType, annotations: _, _meta: metadata):
                var name = metadata?["name"] as? String ?? ""
                if name.isEmpty {
                    name = String(localized: "Tool Provided Image")
                    name += " " + mimeType
                }
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = AttachmentDataParser.decodeData(from: dataString), UIImage(data: data) != nil {
                    images.append(.init(name: name, data: data, mimeType: mimeType.nilIfEmpty))
                } else {
                    Logger.model.errorFile("failed to parse image data from string")
                }
            case let .audio(data: dataString, mimeType: mimeType, annotations: _, _meta: _):
                var name = String(localized: "Tool Provided Audio")
                if !mimeType.isEmpty {
                    name += " " + mimeType
                }
                name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                if let data = AttachmentDataParser.decodeData(from: dataString) {
                    audio.append(.init(name: name, data: data, mimeType: mimeType.nilIfEmpty))
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
                let annotationsValue = annotations
                    .flatMap { try? JSONEncoder().encode($0) }
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
                let titleValue = title.map { String(describing: $0) } ?? ""
                textContent.append(
                    """
                    [\(titleValue) \(name) \(mimeType ?? "application/resources")](\(uri))
                    \(description ?? "")
                    Annotations: \(annotationsValue)
                    """,
                )
            }
        }
        return ModelToolOutput(text: textContent.joined(separator: "\n"), images: images, audio: audio)
    }
}

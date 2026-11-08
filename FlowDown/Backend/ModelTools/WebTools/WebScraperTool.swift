//
//  WebScraperTool.swift
//  FlowDown
//
//  Created on 2/28/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import ScrubberKit

final class MTWebScraperTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Web Reader")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "scrape_web_page",
            description: "Fetch a web page and return its text content, for reading articles or extracting data.",
            parameters: [
                "type": "object",
                "properties": [
                    "url": [
                        "type": "string",
                        "description": "Page URL, HTTP or HTTPS.",
                    ],
                ],
                "required": ["url"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "globe",
            title: "Web Reader",
            explain: "Allows LLM to fetch and read content from web pages.",
            key: "wiki.qaq.ModelTools.WebScraperTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    func execute(_ arguments: ModelToolArguments, context _: ModelToolContext) async throws -> ModelToolOutput {
        guard let urlString = arguments.string("url"),
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil
        else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid URL provided"))
        }

        guard let doc = await scrape(url: url) else {
            throw ModelToolError.failure(String(localized: "Failed to fetch the web content."))
        }

        let maxSize = 32768
        let truncatedContent = doc.textDocument.count > maxSize
            ? String(doc.textDocument.prefix(maxSize)) + "...\n"
                + String(localized: "Content truncated due to excessive length.")
            : doc.textDocument

        return ModelToolOutput(text: String(localized: """
        Web Content from: \(url.absoluteString)
        Title: \(doc.title)

        \(truncatedContent)
        """))
    }

    @MainActor
    private func scrape(url: URL) async -> Scrubber.Document? {
        await withCheckedContinuation { continuation in
            Scrubber.document(for: url) { continuation.resume(returning: $0) }
        }
    }
}

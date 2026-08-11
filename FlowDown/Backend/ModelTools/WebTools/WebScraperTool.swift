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
import UIKit

class MTWebScraperTool: ModelTool, @unchecked Sendable {
    override var interfaceName: String {
        String(localized: "Web Reader")
    }

    override var definition: ChatRequestBody.Tool {
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

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "globe",
            title: "Web Reader",
            explain: "Allows LLM to fetch and read content from web pages.",
            key: "wiki.qaq.ModelTools.WebScraperTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with input: String, anchorTo _: UIView) async throws -> String {
        guard let json = decodeArguments(input),
              let urlString = json["url"] as? String,
              let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme.lowercased()),
              url.host != nil
        else {
            throw NSError(
                domain: "MTWebScraperTool", code: 400, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid URL provided"),
                ],
            )
        }

        return try await scrapeWithUserInteraction(url: url)
    }

    @MainActor
    func scrapeWithUserInteraction(url: URL) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            Scrubber.document(for: url) { doc in
                guard let doc else {
                    continuation.resume(throwing: ModelToolError.failure(String(localized: "Failed to fetch the web content.")))
                    return
                }

                let maxSize = 32768
                let truncatedContent = doc.textDocument.count > maxSize
                    ? String(doc.textDocument.prefix(maxSize)) + "..." + "\n" + String(localized: "Content truncated due to excessive length.")
                    : doc.textDocument

                let result = String(localized: """
                Web Content from: \(url.absoluteString)
                Title: \(doc.title)

                \(truncatedContent)
                """)
                continuation.resume(returning: result)
            }
        }
    }
}

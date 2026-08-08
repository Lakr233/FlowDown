//
//  MTWebSearchTool.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
@preconcurrency import ScrubberKit
import Storage
import UIKit
import XMLCoder

class MTWebSearchTool: ModelTool, @unchecked Sendable {
    override var shortDescription: String {
        String(localized: "Web Search")
    }

    override var interfaceName: String {
        String(localized: "Web Search")
    }

    override var definition: ChatRequestBody.Tool {
        .function(
            name: "web_search",
            description: """
            Searches the web for current information based on the provided query. This tool can help find up-to-date information, news, facts, or any other content available on the internet.
            """,
            parameters: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "The search query to look for on the web. Should be clear and specific to get the best results.",
                    ],
                ],
                "required": ["query"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    override class var controlObject: ConfigurableObject {
        .init(
            icon: "magnifyingglass",
            title: "Web Search",
            explain: "Allows LLM to search the web for up-to-date information.",
            key: "wiki.qaq.ModelTools.WebSearchTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    override func execute(with _: String, anchorTo _: UIView) async throws -> String {
        fatalError("MTWebSearchTool must be specially handled and cannot be executed directly.")
    }

    nonisolated func execute(
        with input: String,
        session: ConversationSession,
        webSearchMessage: Message,
        anchorTo messageListView: MessageListView,
    ) async throws -> [Scrubber.Document] {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = json["query"] as? String
        else {
            throw NSError(
                domain: "MTWebSearchTool",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid parameters"],
            )
        }

        var status = webSearchMessage.webSearchStatus
        status.queries = [query]
        webSearchMessage.assign(\.webSearchStatus, to: status)

        await session.requestUpdate(view: messageListView)

        var webSearchResults: [Scrubber.Document] = []
        let onSetWebContents: ([Scrubber.Document]) -> Void = { documents in
            webSearchResults.append(contentsOf: documents)
            let storableContent: [Message.WebSearchStatus.SearchResult] = documents.map { doc in
                .init(title: doc.title, url: doc.url)
            }

            var status = webSearchMessage.webSearchStatus
            status.searchResults.append(contentsOf: storableContent)
            webSearchMessage.assign(\.webSearchStatus, to: status)
        }

        for try await phase in await messageListView.session.gatheringWebContent(
            searchQueries: [query],
            onSetWebDocumentResult: onSetWebContents,
        ) {
            var status = webSearchMessage.webSearchStatus
            status.currentSource = phase.currentSource
            status.numberOfSource = phase.numberOfSource
            status.numberOfWebsites = phase.numberOfWebsites
            status.currentQuery = phase.query
            status.currentQueryBeginDate = phase.queryBeginDate
            status.numberOfResults = phase.numberOfResults
            status.proccessProgress = max(0.1, phase.proccessProgress)
            webSearchMessage.assign(\.webSearchStatus, to: status)
            await session.requestUpdate(view: messageListView)
        }

        var statusFinal = webSearchMessage.webSearchStatus
        statusFinal.proccessProgress = 1.0
        webSearchMessage.assign(\.webSearchStatus, to: statusFinal)
        await session.requestUpdate(view: messageListView)

        if webSearchResults.isEmpty {
            await session.requestUpdate(view: messageListView)
        }

        return webSearchResults
    }
}

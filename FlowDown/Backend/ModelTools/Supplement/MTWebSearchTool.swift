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

final class MTWebSearchTool: ConfigurableModelTool, @unchecked Sendable {
    var interfaceName: String {
        String(localized: "Web Search")
    }

    var definition: ChatRequestBody.Tool {
        .function(
            name: "web_search",
            description: "Search the web for current information, news and facts.",
            parameters: [
                "type": "object",
                "properties": [
                    "query": [
                        "type": "string",
                        "description": "Search query, clear and specific.",
                    ],
                ],
                "required": ["query"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    var transcriptRole: Message.Role {
        .webSearch
    }

    static var controlObject: ConfigurableObject {
        .init(
            icon: "magnifyingglass",
            title: "Web Search",
            explain: "Allows LLM to search the web for up-to-date information.",
            key: "wiki.qaq.ModelTools.WebSearchTool.enabled",
            defaultValue: true,
            annotation: .toggle,
        )
    }

    /// Runs in a conversation only: the search reports its progress on the
    /// call's row, and the pages it reads become citable web documents.
    func execute(_ arguments: ModelToolArguments, context: ModelToolContext) async throws -> ModelToolOutput {
        guard let session = context.session, let row = context.row else {
            assertionFailure("web search runs in a conversation")
            throw ModelToolError.failure("Web search runs in a conversation only.")
        }
        guard let query = arguments.nonEmptyString("query") else {
            throw ModelToolError.invalidArguments(String(localized: "Invalid input parameters"))
        }

        do {
            let documents = try await search(query: query, session: session, row: row)
            guard !documents.isEmpty else {
                return ModelToolOutput(text: String(localized: "Web search returned no results."))
            }
            let archives = documents.map { document in
                session.formatAsWebArchive(
                    document: document.textDocument,
                    title: document.title,
                    atIndex: session.requestLinkContentIndex(document.url),
                )
            }
            return ModelToolOutput(text: archives.joined(separator: "\n"))
        } catch {
            row.markModified()
            await session.requestUpdate()
            throw error
        }
    }

    private func search(
        query: String,
        session: ConversationSession,
        row: Message,
    ) async throws -> [Scrubber.Document] {
        var status = row.webSearchStatus
        status.queries = [query]
        row.assign(\.webSearchStatus, to: status)
        await session.requestUpdate()

        var webSearchResults: [Scrubber.Document] = []
        let onSetWebContents: ([Scrubber.Document]) -> Void = { documents in
            webSearchResults.append(contentsOf: documents)
            let storableContent: [Message.WebSearchStatus.SearchResult] = documents.map { doc in
                .init(title: doc.title, url: doc.url)
            }

            var status = row.webSearchStatus
            status.searchResults.append(contentsOf: storableContent)
            row.assign(\.webSearchStatus, to: status)
        }

        for await phase in session.gatheringWebContent(
            searchQueries: [query],
            onSetWebDocumentResult: onSetWebContents,
        ) {
            var status = row.webSearchStatus
            status.currentSource = phase.currentSource
            status.numberOfSource = phase.numberOfSource
            status.numberOfWebsites = phase.numberOfWebsites
            status.currentQuery = phase.query
            status.currentQueryBeginDate = phase.queryBeginDate
            status.numberOfResults = phase.numberOfResults
            status.proccessProgress = phase.proccessProgress
            row.assign(\.webSearchStatus, to: status)
            await session.requestUpdate()
        }

        // Cancelling ends the stream without an error: the search did not
        // finish, so it must not read as one that found nothing.
        try Task.checkCancellation()

        var statusFinal = row.webSearchStatus
        statusFinal.proccessProgress = 1.0
        row.assign(\.webSearchStatus, to: statusFinal)
        await session.requestUpdate()

        return webSearchResults
    }
}

//
//  ConversationSession+WebSearch.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Combine
import Foundation
import RichEditor
@preconcurrency import ScrubberKit
import Storage
import XMLCoder

// MARK: - XML Models for Web Search

private struct WebSearchResponse: Codable {
    var search_required: Bool
    var queries: QueryList

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // 容错处理 search_required 字段
        if let boolValue = try? container.decode(Bool.self, forKey: .search_required) {
            search_required = boolValue
        } else if let stringValue = try? container.decode(String.self, forKey: .search_required) {
            search_required = stringValue.lowercased() != "false"
        } else {
            search_required = true // 默认值
        }

        // 容错处理 queries 字段
        if let queriesValue = try? container.decode(QueryList.self, forKey: .queries) {
            queries = queriesValue
        } else {
            queries = QueryList(query: [])
        }

        if !queries.query.isEmpty, !search_required {
            search_required = true
        }
    }

    private enum CodingKeys: String, CodingKey {
        case search_required
        case queries
    }

    struct QueryList: Codable {
        var query: [String]

        init(query: [String]) {
            self.query = query
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let singleQuery = try? container.decode(String.self, forKey: .query) {
                query = [singleQuery]
            } else if let queryArray = try? container.decode([String].self, forKey: .query) {
                query = queryArray
            } else {
                query = []
            }
        }

        private enum CodingKeys: String, CodingKey {
            case query
        }
    }
}

private struct WebSearchRequest: Codable {
    let task: String
    let user_input: String
    let attached_documents: [AttachedDocument]?
    let previous_messages: [PreviousMessage]?

    private enum CodingKeys: String, CodingKey {
        case task
        case user_input
        case attached_documents
        case previous_messages
    }

    struct AttachedDocument: Codable {
        let id: Int
        let content: String

        private enum CodingKeys: String, CodingKey {
            case id
            case content = ""
        }
    }

    struct PreviousMessage: Codable {
        let id: Int
        let content: String

        private enum CodingKeys: String, CodingKey {
            case id
            case content = ""
        }
    }
}

// MARK: - Web Search Query Generation

extension ConversationSessionManager.Session {
    struct TemplateItem {
        enum Participant: String, Codable {
            case system
            case user
            case assistant
        }

        let participant: Participant
        let document: String
    }

    private func generateWebSearchTemplate(
        input: String,
        documents: [String],
        previousMessages: [String]
    ) -> [TemplateItem] {
        // prompt depends on sensitivity
        let sensitivity = ModelManager.shared.searchSensitivity
        let task = sensitivity.promptTemplate

        let attachedDocuments = documents.isEmpty ? nil : documents.enumerated().map { index, content in
            WebSearchRequest.AttachedDocument(id: index, content: content)
        }

        let previousMessagesData = previousMessages.isEmpty ? nil : previousMessages.enumerated().map { index, content in
            WebSearchRequest.PreviousMessage(id: index, content: content)
        }

        let webSearchRequest = WebSearchRequest(
            task: task,
            user_input: input,
            attached_documents: attachedDocuments,
            previous_messages: previousMessagesData
        )

        let encoder = XMLEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let xmlData = try encoder.encode(webSearchRequest, withRootKey: "web_search_request")
            let xmlString = String(data: xmlData, encoding: .utf8) ?? ""

            return [
                .init(
                    participant: .system,
                    document: """
                    \(task)

                    Current date and time: \(DateFormatter.localizedString(from: Date(), dateStyle: .full, timeStyle: .full))
                    Current locale: \(Locale.current.identifier)
                    Application name: \(Bundle.main.infoDictionary?["CFBundleName"] as? String ?? "unknown AI app")

                    Additional User Request: \(ModelManager.shared.additionalPrompt)

                    Important: Consider all provided context including conversation history and attached documents when determining if web search is needed and what queries to generate.
                    """
                ),
                .init(participant: .user, document: xmlString),
            ]
        } catch {
            Logger.network.errorFile("failed to encode web search request: \(error)")
            return []
        }
    }
}

extension ConversationSessionManager.Session {
    struct WebSearchPhase: Hashable {
        var query: Int = 0
        var queryBeginDate: Date = .init(timeIntervalSince1970: 0)
        /// The number of queries to be processed.
        var numberOfQueries: Int = 0
        var currentSource: Int = 0
        var numberOfSource: Int = 0
        var numberOfWebsites: Int = 0
        var numberOfResults: Int = 0
        var proccessProgress: Double = 0
    }

    func gatheringWebContent(
        searchQueries: [String],
        onSetWebDocumentResult: @escaping ([Scrubber.Document]) -> Void
    ) -> AsyncStream<WebSearchPhase> {
        .init { cont in
            Task.detached {
                var results: [Scrubber.Document] = []

                guard !searchQueries.isEmpty else {
                    onSetWebDocumentResult([])
                    return
                }

                let eachLimit = Int(max(3, ScrubberConfiguration.limitConfigurableObjectValue / searchQueries.count))
                Logger.network.infoFile("web search has limited \(eachLimit) for each query")

                var phase = WebSearchPhase()
                phase.numberOfQueries = searchQueries.count
                for (idx, searchQuery) in searchQueries.enumerated() {
                    try self.checkCancellation()
                    phase.query = idx
                    phase.queryBeginDate = .init()
                    phase.numberOfSource = 0
                    phase.numberOfWebsites = 0
                    phase.proccessProgress = 0.1
                    cont.yield(phase)
                    let urlsReranker = URLsReranker(question: searchQuery, keepKPerHostname: 4)
                    let scrubber = Scrubber(query: searchQuery, options: .init(urlsReranker: urlsReranker))
                    await withTaskCancellationHandler {
                        await withCheckedContinuation { innerCont in
                            DispatchQueue.main.async {
                                scrubber.run(limitation: eachLimit) { docs in
                                    results.append(contentsOf: docs)
                                    innerCont.resume()
                                } onProgress: { overall in
                                    let searchCompleted = scrubber.progress.engineStatusCompletedCount
                                    let searchTotal = scrubber.progress.engineStatus.count
                                    let websiteTotal = scrubber.progress.fetchedStatus.count
                                    phase.proccessProgress = max(0.1, overall.fractionCompleted)
                                    phase.currentSource = searchCompleted
                                    phase.numberOfSource = searchTotal
                                    phase.numberOfWebsites = websiteTotal
                                    cont.yield(phase)
                                }
                            }
                        }
                    } onCancel: {
                        Logger.network.errorFile("cancelling web search due to task is cancelled")
                        scrubber.cancel()
                    }
                }

                results.shuffle()
                onSetWebDocumentResult(results)

                phase.numberOfResults = results.count
                phase.queryBeginDate = .init(timeIntervalSince1970: 0)
                cont.yield(phase)

                cont.finish()
            }
        }
    }

    func generateSearchQueries(for query: String, attachments: [String], previousMessages: [String]) async -> (queries: [String], searchRequired: Bool?) {
        let messages: [ChatRequestBody.Message] = generateWebSearchTemplate(
            input: query,
            documents: attachments,
            previousMessages: previousMessages
        ).map {
            switch $0.participant {
            case .system: .system(content: .text($0.document))
            case .assistant: .assistant(content: .text($0.document))
            case .user: .user(content: .text($0.document))
            }
        }

        guard let model = models.auxiliary else { return ([], nil) }

        do {
            let ans = try await ModelManager.shared.infer(
                with: model,
                maxCompletionTokens: 256,
                input: messages
            )

            let content = ans.content.trimmingCharacters(in: .whitespacesAndNewlines)

            if let (queries, searchRequired) = extractQueriesFromXMLWithSearchRequired(content) {
                return (validateQueries(queries), searchRequired)
            }

            let queries = content
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            return (validateQueries(queries), nil)
        } catch {
            Logger.network.errorFile("failed to generate search queries: \(error)")
            return ([], nil)
        }
    }

    private func extractQueriesFromXMLWithSearchRequired(_ xmlString: String) -> (queries: [String], searchRequired: Bool)? {
        if let result = extractQueriesUsingXMLCoderWithSearchRequired(xmlString) {
            return result
        }
        return extractQueriesUsingRegexWithSearchRequired(xmlString)
    }

    private func extractQueriesUsingXMLCoderWithSearchRequired(_ xmlString: String) -> (queries: [String], searchRequired: Bool)? {
        let decoder = XMLDecoder()

        if let data = xmlString.data(using: .utf8),
           let searchResponse = try? decoder.decode(WebSearchResponse.self, from: data)
        {
            let queries = searchResponse.queries.query.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return (queries, searchResponse.search_required)
        }
        return nil
    }

    private func extractQueriesUsingRegexWithSearchRequired(_ xmlString: String) -> (queries: [String], searchRequired: Bool)? {
        var searchRequired = true

        let searchRequiredPattern = #"<search_required>(.*?)</search_required>"#
        if let searchRequiredRegex = try? NSRegularExpression(pattern: searchRequiredPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let searchRequiredMatch = searchRequiredRegex.firstMatch(in: xmlString, options: [], range: NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)),
           let searchRequiredRange = Range(searchRequiredMatch.range(at: 1), in: xmlString)
        {
            let searchRequiredValue = String(xmlString[searchRequiredRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            searchRequired = searchRequiredValue != "false"
        }

        let pattern = #"<queries>(.*?)</queries>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else {
            return nil
        }
        guard let queriesRange = Range(match.range(at: 1), in: xmlString) else {
            return nil
        }
        let queriesText = String(xmlString[queriesRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPattern = #"<query>(.*?)</query>"#
        guard let queryRegex = try? NSRegularExpression(pattern: queryPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let queryRange = NSRange(queriesText.startIndex ..< queriesText.endIndex, in: queriesText)
        let matches = queryRegex.matches(in: queriesText, options: [], range: queryRange)
        let queries = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: queriesText) else { return nil }
            return String(queriesText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        return (queries, searchRequired)
    }

    private func extractQueriesFromXML(_ xmlString: String) -> [String]? {
        if let queries = extractQueriesUsingXMLCoder(xmlString) {
            return queries
        }
        return extractQueriesUsingRegex(xmlString)
    }

    private func extractQueriesUsingXMLCoder(_ xmlString: String) -> [String]? {
        let decoder = XMLDecoder()

        if let data = xmlString.data(using: .utf8),
           let searchResponse = try? decoder.decode(WebSearchResponse.self, from: data)
        {
            guard searchResponse.search_required else {
                return []
            }
            return searchResponse.queries.query.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return nil
    }

    private func extractQueriesUsingRegex(_ xmlString: String) -> [String]? {
        let searchRequiredPattern = #"<search_required>(.*?)</search_required>"#
        if let searchRequiredRegex = try? NSRegularExpression(pattern: searchRequiredPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
           let searchRequiredMatch = searchRequiredRegex.firstMatch(in: xmlString, options: [], range: NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)),
           let searchRequiredRange = Range(searchRequiredMatch.range(at: 1), in: xmlString)
        {
            let searchRequiredValue = String(xmlString[searchRequiredRange]).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if searchRequiredValue == "false" {
                return []
            }
        }
        let pattern = #"<queries>(.*?)</queries>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(xmlString.startIndex ..< xmlString.endIndex, in: xmlString)
        guard let match = regex.firstMatch(in: xmlString, options: [], range: range) else {
            return nil
        }
        guard let queriesRange = Range(match.range(at: 1), in: xmlString) else {
            return nil
        }
        let queriesText = String(xmlString[queriesRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let queryPattern = #"<query>(.*?)</query>"#
        guard let queryRegex = try? NSRegularExpression(pattern: queryPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let queryRange = NSRange(queriesText.startIndex ..< queriesText.endIndex, in: queriesText)
        let matches = queryRegex.matches(in: queriesText, options: [], range: queryRange)
        let queries = matches.compactMap { match -> String? in
            guard let range = Range(match.range(at: 1), in: queriesText) else { return nil }
            return String(queriesText[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        return queries.isEmpty ? nil : queries
    }

    private func validateQueries(_ queries: [String]) -> [String] {
        // Validate query constraints
        let validQueries = queries.filter { query in
            query.count <= 25 && query.count >= 2
        }

        // Limit to maximum 3 queries
        return Array(validQueries.prefix(3))
    }
}

extension ConversationSession {
    func formatAsWebArchive(document: String, title: String, atIndex index: Int) -> String {
        """
        <web_document id="\(index)">
        <title>\(title)</title>
        <note>\(String(localized: "This document is provided by system or tool call, please cite the id with [^\(index)] format if used."))</note>
        <content>
        \(document)
        </content>
        </web_document>
        """
    }

    func preprocessSearchQueries(
        _ currentMessageListView: MessageListView,
        _ object: inout RichEditorView.Object,
        requestLinkContentIndex: @escaping (URL) -> Int
    ) async throws {
        guard case let .bool(value) = object.options[.browsing], value else {
            return
        }

        // 检查是否同时启用了工具调用，如果是，则跳过预处理阶段的网络搜索
        if case let .bool(tools) = object.options[.tools], tools {
            // 当同时启用工具调用和网络搜索时，让模型决定何时使用网络搜索工具
            Logger.network.infoFile("Web search will be handled as a tool call")
            return
        }

        try checkCancellation()
        await currentMessageListView.loading()

        // 获取更完整的上下文信息，包括角色和时间戳
        let prevMsgs = messages
            .filter { [.user, .assistant].contains($0.role) }
            .filter { !$0.document.isEmpty }
            .suffix(5) // 限制最近 n 条消息避免上下文过长
            .map { message in
                let rolePrefix = message.role == .user ? "[User]" : "[Assistant]"
                return "\(rolePrefix): \(message.document)"
            }

        // 获取附件的完整文本表示
        let attachmentTexts = object.attachments.compactMap { attachment -> String? in
            guard !attachment.textRepresentation.isEmpty else { return nil }
            return "Document: \(attachment.name)\nContent: \(attachment.textRepresentation)"
        }

        let searchResult = await generateSearchQueries(
            for: object.text,
            attachments: attachmentTexts,
            previousMessages: prevMsgs
        )

        let searchQueries = searchResult.queries
        let searchRequired = searchResult.searchRequired

        if let required = searchRequired, !required {
            Logger.network.infoFile("model determined no web search is needed")
            let message = appendNewMessage(role: .assistant) {
                $0.update(\.document, to: String(localized: "I have determined that no web search is needed for this query."))
            }
            message.modelIdentifier = models.auxiliary
            await requestUpdate(view: currentMessageListView)
            return
        }

        guard !searchQueries.isEmpty else {
            Logger.network.errorFile("failed to generate search queries")
            let message = appendNewMessage(role: .assistant) {
                $0.update(\.document, to: String(localized: "I was unable to generate appropriate search queries for this request."))
            }
            message.modelIdentifier = models.auxiliary
            await requestUpdate(view: currentMessageListView)
            return
        }

        let webSearchMessage = appendNewMessage(role: .webSearch) {
            var status = $0.webSearchStatus
            status.queries = searchQueries
            $0.assign(\.webSearchStatus, to: status)
        }

        await requestUpdate(view: currentMessageListView)

        var webAttachments: [RichEditorView.Object.Attachment] = []

        let onSetWebContents: ([Scrubber.Document]) -> Void = { documents in
            Logger.network.infoFile("setting \(documents.count) search result")
            for doc in documents {
                let index = requestLinkContentIndex(doc.url)
                webAttachments.append(.init(
                    type: .text,
                    name: doc.title,
                    previewImage: .init(),
                    imageRepresentation: .init(),
                    textRepresentation: self.formatAsWebArchive(
                        document: doc.textDocument,
                        title: doc.title,
                        atIndex: index
                    ),
                    storageSuffix: UUID().uuidString
                ))
            }
            let storableContent: [Message.WebSearchStatus.SearchResult] = documents.map { doc in
                .init(title: doc.title, url: doc.url)
            }
            var updatedStatus = webSearchMessage.webSearchStatus
            updatedStatus.searchResults.append(contentsOf: storableContent)
            webSearchMessage.assign(\.webSearchStatus, to: updatedStatus)
        }

        for try await phase in gatheringWebContent(
            searchQueries: searchQueries,
            onSetWebDocumentResult: onSetWebContents
        ) {
            try checkCancellation()
            var status = webSearchMessage.webSearchStatus
            status.currentSource = phase.currentSource
            status.numberOfSource = phase.numberOfSource
            status.numberOfWebsites = phase.numberOfWebsites
            status.currentQuery = phase.query
            status.currentQueryBeginDate = phase.queryBeginDate
            status.numberOfResults = phase.numberOfResults
            status.proccessProgress = max(0.1, phase.proccessProgress)
            webSearchMessage.assign(\.webSearchStatus, to: status)
            await requestUpdate(view: currentMessageListView)
        }
        var finalStatus = webSearchMessage.webSearchStatus
        finalStatus.proccessProgress = 0
        webSearchMessage.assign(\.webSearchStatus, to: finalStatus)
        await requestUpdate(view: currentMessageListView)

        object.attachments.append(contentsOf: webAttachments)

        if webAttachments.isEmpty {
            var errorStatus = webSearchMessage.webSearchStatus
            errorStatus.proccessProgress = -1
            webSearchMessage.assign(\.webSearchStatus, to: errorStatus)
            throw NSError(
                domain: "Inference Service",
                code: -1,
                userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "No web search results."),
                ]
            )
        }

        await currentMessageListView.loading(with: String(localized: "Processing Web Search Results") + "...")
    }
}

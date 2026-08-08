//
//  ConversationSession+WebSearch.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import ChatClientKit
import Combine
import Foundation
@preconcurrency import ScrubberKit
import Storage

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
        onSetWebDocumentResult: @escaping ([Scrubber.Document]) -> Void,
    ) -> AsyncStream<WebSearchPhase> {
        .init { cont in
            let producerTask = Task.detached {
                defer { cont.finish() }
                do {
                    var results: [Scrubber.Document] = []

                    guard !searchQueries.isEmpty else {
                        onSetWebDocumentResult([])
                        return
                    }

                    let eachLimit = await MainActor.run {
                        Int(max(3, ScrubberConfiguration.limitConfigurableObjectValue / searchQueries.count))
                    }
                    Logger.network.infoFile("web search has limited \(eachLimit) for each query")

                    var phase = WebSearchPhase()
                    phase.numberOfQueries = searchQueries.count
                    for (idx, searchQuery) in searchQueries.enumerated() {
                        try self.checkCancellation()
                        try Task.checkCancellation()
                        phase.query = idx
                        phase.queryBeginDate = .init()
                        phase.numberOfSource = 0
                        phase.numberOfWebsites = 0
                        phase.proccessProgress = 0.1
                        cont.yield(phase)
                        let basePhase = phase
                        let urlsReranker = URLsReranker(question: searchQuery, keepKPerHostname: 4)
                        let scrubber = Scrubber(query: searchQuery, options: .init(urlsReranker: urlsReranker))
                        await withTaskCancellationHandler {
                            let docs: [Scrubber.Document] = await withCheckedContinuation { innerCont in
                                Task { @MainActor in
                                    scrubber.run(limitation: eachLimit) { docs in
                                        innerCont.resume(returning: docs)
                                    } onProgress: { overall in
                                        let searchCompleted = scrubber.progress.engineStatusCompletedCount
                                        let searchTotal = scrubber.progress.engineStatus.count
                                        let websiteTotal = scrubber.progress.fetchedStatus.count
                                        var progressPhase = basePhase
                                        progressPhase.proccessProgress = max(0.1, overall.fractionCompleted)
                                        progressPhase.currentSource = searchCompleted
                                        progressPhase.numberOfSource = searchTotal
                                        progressPhase.numberOfWebsites = websiteTotal
                                        cont.yield(progressPhase)
                                    }
                                }
                            }
                            results.append(contentsOf: docs)
                        } onCancel: {
                            Logger.network.errorFile("cancelling web search due to task is cancelled")
                            Task { @MainActor in scrubber.cancel() }
                        }
                    }

                    try Task.checkCancellation()
                    results.shuffle()
                    onSetWebDocumentResult(results)

                    phase.numberOfResults = results.count
                    phase.queryBeginDate = .init(timeIntervalSince1970: 0)
                    cont.yield(phase)
                } catch {
                    Logger.network.errorFile("web search interrupted: \(error)")
                }
            }
            cont.onTermination = { _ in producerTask.cancel() }
        }
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
}

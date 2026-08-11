//
//  RewriteAction.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/30/25.
//

import AlertController
import ChatClientKit
import Foundation
import Storage
import UIKit

enum RewriteAction: String, CaseIterable, Hashable {
    case summarize
    case moreDetails
    case makeProfessional
    case makeFriendly
    case listKeyPointes
    case drawTable
}

extension RewriteAction {
    var title: String {
        switch self {
        case .summarize: String(localized: "Summarize")
        case .moreDetails: String(localized: "Add More Details")
        case .makeProfessional: String(localized: "Make Professional")
        case .makeFriendly: String(localized: "Make Friendly")
        case .listKeyPointes: String(localized: "List Key Points")
        case .drawTable: String(localized: "Draw Table")
        }
    }

    var icon: UIImage? {
        switch self {
        case .summarize: UIImage(systemName: "text.quote")
        case .moreDetails: UIImage(systemName: "plus.square")
        case .makeProfessional: UIImage(systemName: "person.crop.circle.badge.checkmark")
        case .makeFriendly: UIImage(systemName: "person.crop.circle.badge.questionmark")
        case .listKeyPointes: UIImage(systemName: "list.bullet")
        case .drawTable: UIImage(systemName: "tablecells")
        }
    }

    var prompt: String {
        switch self {
        case .summarize:
            String(localized: "Please summarize the following content in a concise and clear manner.")
        case .moreDetails:
            String(localized: "Please add more details and expand on the following content to provide additional information and context.")
        case .makeProfessional:
            String(localized: "Please rewrite the following content in a more professional tone, using formal language and appropriate terminology.")
        case .makeFriendly:
            String(localized: "Please rewrite the following content in a more friendly and approachable tone, making it easy to understand and engaging.")
        case .listKeyPointes:
            String(localized: "Please list the key points from the following content in bullet points or a numbered list for clarity.")
        case .drawTable:
            String(localized: "Please organize the following content into a table, clearly labeling each column and row for easy reference.")
        }
    }
}

extension RewriteAction {
    func send(to session: ConversationSession, message: Message.ID, bindView: MessageListView) {
        guard let model = session.models.chat else {
            let alert = AlertViewController(
                title: "Model Not Available",
                message: "Please select a model to rewrite this message.",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK", attribute: .accent) {
                    context.dispose()
                }
            }
            bindView.parentViewController?.present(alert, animated: true)
            return
        }
        guard let controller = bindView.parentViewController,
              let message = session.message(for: message)
        else {
            assertionFailure()
            return
        }

        let messageBody: [ChatRequestBody.Message] = [
            .system(content: .text(prompt + ConversationManager.markdownOutputGuidelines)),
            .user(content: .text(String(localized: "Please rewrite accordingly"))),
            .user(content: .text(message.document), name: String(localized: "Original Message")),
        ]

        Indicator.progress(
            title: "Rewriting Message",
            controller: controller,
        ) { completionHandler in
            let stream = try await ModelManager.shared.streamingInfer(
                with: model,
                input: messageBody,
            )

            var rewritten = ""
            for try await resp in stream {
                switch resp {
                case let .text(value):
                    rewritten += value
                    message.update(\.document, to: rewritten)
                default:
                    break
                }
                session.notifyMessagesDidChange(scrolling: false)
                session.save()
            }
            session.save()
            await completionHandler {
                session.notifyMessagesDidChange(scrolling: false)
            }
        }
    }
}

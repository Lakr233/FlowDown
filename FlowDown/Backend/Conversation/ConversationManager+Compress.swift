//
//  ConversationManager+Compress.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/30/25.
//

import ChatClientKit
import Foundation
import Storage

extension ConversationManager {
    func compressConversation(
        identifier: Conversation.ID,
        model: ModelManager.ModelIdentifier,
        onConversationCreated: @escaping (Conversation.ID) -> Void,
        completion: @escaping (Result<Conversation.ID, Error>) -> Void,
    ) {
        guard let conv = conversation(identifier: identifier) else {
            assertionFailure()
            completion(.failure(NSError(domain: "ConversationManager", code: 404, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Unknown Error"),
            ])))
            return
        }
        exportConversation(
            identifier: identifier,
            exportFormat: .markdown,
        ) { result in
            switch result {
            case let .success(success):
                self.compressConversation(
                    model: model,
                    title: conv.title,
                    text: success,
                    onConversationCreated: onConversationCreated,
                    completion: completion,
                )
            case let .failure(failure):
                completion(.failure(failure))
            }
        }
    }

    private func compressConversation(
        model: ModelManager.ModelIdentifier,
        title: String,
        text: String,
        onConversationCreated: @escaping (Conversation.ID) -> Void,
        completion: @escaping (Result<Conversation.ID, Error>) -> Void,
    ) {
        let conv = ConversationManager.shared.createNewConversation {
            let icon = "🗜️".textToImage(size: 64)?.pngData() ?? .init()
            $0.update(\.title, to: title)
            $0.update(\.icon, to: icon)
            $0.update(\.shouldAutoRename, to: true)
        }
        let sess = ConversationSessionManager.shared.session(for: conv.id)

        sess.appendNewMessage(role: .hint) {
            $0.update(\.document, to: String(localized: "This conversation is created by compressing \"\(title)\"."))
        }
        sess.save()
        sess.notifyMessagesDidChange()

        let messageBody: [ChatRequestBody.Message] = [
            .system(content: .text(
                String(localized: """
                You are a professional conversation summarization assistant. Please compress and summarize the previous conversation according to the following requirements:

                1. Retain the core information and important conclusions of the conversation; remove irrelevant, repetitive, or redundant content.
                2. Maintain the original logical order and context to ensure the compressed content is easy to understand.
                3. Clearly list any to-do items, decisions, conclusions, or key issues mentioned in the conversation.
                4. Preserve necessary contextual information to avoid loss or misunderstanding due to compression.
                5. Use concise and accurate language; do not add information that was not mentioned or make subjective assumptions.
                6. If the conversation covers multiple topics, organize them into separate sections or bullet points.
                7. Output the summary in structured Markdown format, including titles and bullet points for easy reference.

                Please compress and summarize the content of the "Previous Conversation" according to the above requirements.
                """)
                    + ConversationManager.markdownOutputGuidelines,
            )),
            .user(content: .text(String(localized: "Please summarize the following conversation:"))),
            .user(content: .text(text), name: String(localized: "Previous Conversation")),
        ]

        Task.detached {
            await MainActor.run { onConversationCreated(conv.id) }
            do {
                let stream = try await ModelManager.shared.streamingInfer(
                    with: model,
                    input: messageBody,
                )
                let mess = sess.appendNewMessage(role: .assistant)
                var compressed = ""
                for try await chunk in stream {
                    switch chunk {
                    case let .text(value):
                        compressed += value
                        mess.update(\.document, to: compressed)
                    case let .reasoning(value):
                        mess.update(\.reasoningContent, to: mess.reasoningContent + value)
                    case .tool, .image:
                        break
                    }
                    sess.notifyMessagesDidChange()
                    sess.save()
                }
                sess.notifyMessagesDidChange()
                sess.save()
                await MainActor.run { completion(.success(conv.id)) }
            } catch {
                await MainActor.run {
                    sess.appendNewMessage(role: .assistant) {
                        $0.update(
                            \.document,
                            to: String(localized: "An error occurred during compression: \(error.localizedDescription)"),
                        )
                    }
                    sess.notifyMessagesDidChange()
                    sess.save()
                    completion(.failure(error))
                }
            }
        }
    }
}

extension ConversationManager {
    /// Output rules shared by the rewrite and the compress prompts.
    static let markdownOutputGuidelines: String = [
        "- Do not output any additional text, such as 'Okay' or 'Continue', before the Markdown content.",
        "- Please ensure the output is in Markdown format, including appropriate headings and bullet points.",
        "- Do not output any code blocks or unnecessary formatting.",
        "- Please ensure the output is concise and focused on the key points of the conversation.",
        "**DO NOT START THE OUTPUT WITH ``` NOR ENDING WITH IT**",
    ].joined(separator: "\n")
}

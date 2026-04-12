@testable import FlowDown
import Foundation
@testable import Storage
import Testing

@Suite(.serialized)
struct OnlineModelBackedE2ETests {
    private func withTemporaryCloudModel<T>(
        _ body: @escaping (ModelManager.ModelIdentifier) async throws -> T
    ) async throws -> T {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let model = try OnlineE2ETestSupport.runtimeCloudModel()

        await MainActor.run {
            ModelManager.shared.insertCloudModel(model)
        }

        do {
            let result = try await body(model.id)
            await MainActor.run {
                ModelManager.shared.removeCloudModel(identifier: model.id)
            }
            return result
        } catch {
            await MainActor.run {
                ModelManager.shared.removeCloudModel(identifier: model.id)
            }
            throw error
        }
    }

    @MainActor
    private func makeConversation(
        title: String,
        modelID: ModelManager.ModelIdentifier,
        exchanges: [(Message.Role, String)]
    ) -> Conversation.ID {
        ConversationManager.shouldShowGuideMessage = false
        let conversation = ConversationManager.shared.createNewConversation {
            $0.update(\.title, to: title)
            $0.update(\.modelId, to: modelID)
            $0.update(\.shouldAutoRename, to: false)
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)

        for message in session.messages where message.role == .system || message.role == .assistant {
            session.delete(messageIdentifier: message.objectId)
        }

        for (role, text) in exchanges {
            session.appendNewMessage(role: role) {
                $0.update(\.document, to: text)
            }
        }
        session.save()
        session.notifyMessagesDidChange()
        return conversation.id
    }

    @MainActor
    private func deleteConversationIfPresent(_ identifier: Conversation.ID?) {
        guard let identifier else { return }
        guard ConversationManager.shared.conversation(identifier: identifier) != nil else { return }
        ConversationManager.shared.deleteConversation(identifier: identifier)
    }

    @MainActor
    private func latestAssistantDocument(in conversationID: Conversation.ID) -> String {
        let session = ConversationSessionManager.shared.session(for: conversationID)
        return session.messages
            .filter { $0.role == .assistant }
            .compactMap(\.document)
            .last ?? ""
    }

    @MainActor
    private func compressConversation(
        identifier: Conversation.ID,
        modelID: ModelManager.ModelIdentifier
    ) async throws -> Conversation.ID {
        try await withCheckedThrowingContinuation { continuation in
            ConversationManager.shared.compressConversation(
                identifier: identifier,
                model: modelID,
                onConversationCreated: { _ in },
                completion: { result in
                    continuation.resume(with: result)
                },
            )
        }
    }

    @MainActor
    private func extractTemplate(
        from conversationID: Conversation.ID,
        modelID: ModelManager.ModelIdentifier
    ) async throws -> ChatTemplate {
        guard let conversation = ConversationManager.shared.conversation(identifier: conversationID) else {
            throw NSError(
                domain: "OnlineModelBackedE2ETests",
                code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Conversation not found."],
            )
        }

        return try await withCheckedThrowingContinuation { continuation in
            ChatTemplateManager.shared.createTemplateFromConversation(
                conversation,
                model: modelID,
                completion: { result in
                    continuation.resume(with: result)
                },
            )
        }
    }

    @MainActor
    private func rewriteTemplate(
        _ template: ChatTemplate,
        request: String,
        modelID: ModelManager.ModelIdentifier
    ) async throws -> ChatTemplate {
        try await withCheckedThrowingContinuation { continuation in
            ChatTemplateManager.shared.rewriteTemplate(
                template: template,
                request: request,
                model: modelID,
                completion: { result in
                    continuation.resume(with: result)
                },
            )
        }
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled))
    func `conversation compression produces structured summary from fdmodel runtime`() async throws {
        try await withTemporaryCloudModel { modelID in
            let sourceConversationID = await MainActor.run {
                makeConversation(
                    title: "Atlas delivery review",
                    modelID: modelID,
                    exchanges: [
                        (.user, "Project Atlas ships on June 15. The blockers are login migration, retry handling, and the analytics dashboard."),
                        (.assistant, "Understood. I suggest three workstreams: auth migration, background retry stabilization, and dashboard QA."),
                        (.user, "Action items: Alice owns auth migration, Bob owns retry handling, and Carol owns dashboard QA. Budget stays under 15000 dollars."),
                        (.assistant, "Captured. Final decision: defer SSO polish to phase two and prioritize reliability over new features."),
                    ],
                )
            }

            var compressedConversationID: Conversation.ID?
            do {
                compressedConversationID = try await compressConversation(identifier: sourceConversationID, modelID: modelID)

                let summary = await MainActor.run {
                    latestAssistantDocument(in: compressedConversationID!)
                }

                #expect(!summary.isEmpty)
                #expect(!summary.hasPrefix("```"))
                #expect(summary.contains("#") || summary.contains("- "))
                #expect(summary.localizedCaseInsensitiveContains("Atlas"))
                #expect(
                    summary.localizedCaseInsensitiveContains("Alice")
                        || summary.localizedCaseInsensitiveContains("Bob")
                        || summary.localizedCaseInsensitiveContains("Carol")
                )
            } catch {
                await MainActor.run {
                    deleteConversationIfPresent(compressedConversationID)
                    deleteConversationIfPresent(sourceConversationID)
                }
                throw error
            }

            await MainActor.run {
                deleteConversationIfPresent(compressedConversationID)
                deleteConversationIfPresent(sourceConversationID)
            }
        }
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled))
    func `template extraction returns reusable template from fdmodel runtime`() async throws {
        try await withTemporaryCloudModel { modelID in
            let conversationID = await MainActor.run {
                makeConversation(
                    title: "Kyoto trip planner",
                    modelID: modelID,
                    exchanges: [
                        (.user, "Help me plan a four day Kyoto trip focused on temples, vegetarian food, and a tight budget."),
                        (.assistant, "I can build a day by day Kyoto itinerary with transit advice, low-cost stays, and vegetarian restaurant ideas."),
                        (.user, "Please optimize for walking routes, train passes, and one rainy day backup plan."),
                        (.assistant, "Understood. I will prioritize clustered neighborhoods, JR and subway pass guidance, and indoor backups."),
                    ],
                )
            }

            do {
                let template = try await extractTemplate(from: conversationID, modelID: modelID)

                let combined = [template.name, template.prompt].joined(separator: " ").lowercased()

                #expect(!template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!template.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                #expect(!template.prompt.contains("<template>"))
                #expect(
                    combined.contains("travel")
                        || combined.contains("trip")
                        || combined.contains("itinerary")
                        || combined.contains("kyoto")
                )
            } catch {
                await MainActor.run {
                    deleteConversationIfPresent(conversationID)
                }
                throw error
            }

            await MainActor.run {
                deleteConversationIfPresent(conversationID)
            }
        }
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled))
    func `template rewrite keeps the name when only prompt changes`() async throws {
        try await withTemporaryCloudModel { modelID in
            let original = ChatTemplate()
                .with {
                    $0.name = "Weekly Status"
                    $0.prompt = "Turn rough weekly notes into a polished status update with accomplishments, risks, and next steps."
                }

            let rewritten = try await rewriteTemplate(
                original,
                request: "Keep the template name unchanged. Rewrite only the prompt so it becomes more concise and more executive.",
                modelID: modelID,
            )

            #expect(rewritten.name == original.name)
            #expect(!rewritten.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(rewritten.prompt != original.prompt)
            #expect(!rewritten.prompt.contains("<template>"))
            #expect(!rewritten.prompt.contains("</template>"))
        }
    }
}

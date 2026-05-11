@testable import FlowDown
import Foundation
@testable import Storage
import Testing

@Suite(.serialized)
struct OnlineModelBackedE2ETests {
    static let responseFormats = OnlineE2ETestSupport.responseFormats

    private func withTemporaryCloudModel<T>(
        responseFormat: CloudModel.ResponseFormat,
        _ body: @escaping (ModelManager.ModelIdentifier) async throws -> T,
    ) async throws -> T {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()
        let model = try OnlineE2ETestSupport.runtimeCloudModel(responseFormat: responseFormat)

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
        exchanges: [(Message.Role, String)],
        shouldAutoRename: Bool = false,
        clearIcon: Bool = false,
    ) -> Conversation.ID {
        ConversationManager.shouldShowGuideMessage = false
        let conversation = ConversationManager.shared.createNewConversation {
            $0.update(\.title, to: title)
            $0.update(\.modelId, to: modelID)
            $0.update(\.shouldAutoRename, to: shouldAutoRename)
            if clearIcon {
                $0.update(\.icon, to: Data())
            }
        }
        let session = ConversationSessionManager.shared.session(for: conversation.id)
        session.models.chat = modelID
        session.models.auxiliary = modelID

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
        modelID: ModelManager.ModelIdentifier,
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
        modelID: ModelManager.ModelIdentifier,
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
        modelID: ModelManager.ModelIdentifier,
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

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineModelBackedE2ETests.responseFormats)
    @MainActor
    func `auto rename e2e updates title and icon with one metadata generation flow`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))
        try await withTemporaryCloudModel(responseFormat: responseFormat) { modelID in
            let originalTitle = "Pending auto rename \(UUID().uuidString.prefix(8))"
            let conversationID = makeConversation(
                title: originalTitle,
                modelID: modelID,
                exchanges: [
                    (.user, "Help me name this chat. We are planning a four day Kyoto trip focused on temples, vegetarian food, and a lean budget."),
                    (.assistant, "Plan saved: four days in Kyoto with temple visits, affordable vegetarian spots, neighborhood-based walking routes, and rainy day backups."),
                ],
                shouldAutoRename: true,
                clearIcon: true,
            )

            defer {
                deleteConversationIfPresent(conversationID)
            }

            let session = ConversationSessionManager.shared.session(for: conversationID)
            #expect(session.shouldAutoRename)

            await session.updateTitleAndIcon()

            let updatedConversation = try #require(ConversationManager.shared.conversation(identifier: conversationID))

            #expect(!updatedConversation.shouldAutoRename)
            #expect(!updatedConversation.title.isEmpty)
            #expect(updatedConversation.title != originalTitle)
            #expect(updatedConversation.title.count <= 32)
            #expect(!updatedConversation.title.contains("<title>"))
            #expect(!updatedConversation.title.contains("**"))
            #expect(!updatedConversation.icon.isEmpty)
        }
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineModelBackedE2ETests.responseFormats)
    func `conversation compression produces structured summary from fdmodel runtime`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))
        try await withTemporaryCloudModel(responseFormat: responseFormat) { modelID in
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

                let resolvedCompressedID = compressedConversationID!
                let summary = await MainActor.run {
                    latestAssistantDocument(in: resolvedCompressedID)
                }

                #expect(!summary.isEmpty)
                #expect(!summary.hasPrefix("```"))
                #expect(summary.contains("#") || summary.contains("- "))
                #expect(summary.localizedCaseInsensitiveContains("Atlas"))
                #expect(
                    summary.localizedCaseInsensitiveContains("Alice")
                        || summary.localizedCaseInsensitiveContains("Bob")
                        || summary.localizedCaseInsensitiveContains("Carol"),
                )
            } catch {
                let cleanupID = compressedConversationID
                await MainActor.run {
                    deleteConversationIfPresent(cleanupID)
                    deleteConversationIfPresent(sourceConversationID)
                }
                throw error
            }

            let finalCleanupID = compressedConversationID
            await MainActor.run {
                deleteConversationIfPresent(finalCleanupID)
                deleteConversationIfPresent(sourceConversationID)
            }
        }
    }

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineModelBackedE2ETests.responseFormats)
    func `template extraction returns reusable template from fdmodel runtime`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))
        try await withTemporaryCloudModel(responseFormat: responseFormat) { modelID in
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
                        || combined.contains("kyoto"),
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

    @Test(.enabled(if: OnlineE2ETestSupport.isEnabled), arguments: OnlineModelBackedE2ETests.responseFormats)
    func `template rewrite keeps the name when only prompt changes`(
        responseFormat: CloudModel.ResponseFormat,
    ) async throws {
        try #require(OnlineE2ETestSupport.isEnabled(for: responseFormat))
        try await withTemporaryCloudModel(responseFormat: responseFormat) { modelID in
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

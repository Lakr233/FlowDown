import AppIntents
import Foundation

struct GenerateNewConversationLinkIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Create Conversation Link")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Create a FlowDown deep link that starts a new conversation."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Initial Message"),
        requestValueDialog: IntentDialog("What message should FlowDown pre-fill?")
    )
    var message: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Create conversation link with \(\.$message)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedMessage = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        let initialMessage = trimmedMessage?.isEmpty == false ? trimmedMessage : nil

        let url = try ShortcutUtilities.newConversationURL(initialMessage: initialMessage)
        let link = url.absoluteString

        let dialogMessage = String(
            localized: "Use the Open URL action with \(link) to launch FlowDown and start a conversation."
        )

        let dialog = IntentDialog(.init(stringLiteral: dialogMessage))
        return .result(value: link, dialog: dialog)
    }
}

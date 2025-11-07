import AppIntents
import Foundation

struct FetchLastConversationDetailsIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Fetch Last Conversation")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Return the full transcript of the most recent FlowDown conversation."
        )
    )

    static var parameterSummary: some ParameterSummary {
        Summary("Fetch latest conversation details")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let transcript = try ShortcutUtilities.latestConversationTranscript()
        let dialog = IntentDialog(.init(stringLiteral: transcript))
        return .result(value: transcript, dialog: dialog)
    }
}

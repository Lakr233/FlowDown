import AppIntents
import Foundation

struct SetConversationModelIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Set Conversation Model")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Choose the default model for new conversations."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should be the default?")
    )
    var model: ShortcutsEntities.ModelEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Set conversation model to \(\.$model)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let modelID = model.id

        let displayName = await MainActor.run { () -> String in
            ModelManager.ModelIdentifier.defaultModelForConversation = modelID
            return ModelManager.shared.modelName(identifier: modelID)
        }

        let message = String(localized: "Default conversation model set to \(displayName).")
        let dialog = IntentDialog(.init(stringLiteral: message))
        return .result(value: message, dialog: dialog)
    }
}

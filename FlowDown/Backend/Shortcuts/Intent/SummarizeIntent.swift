import AppIntents
import Foundation

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Summarize Text")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Summarize content into a short paragraph."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should summarize the text?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What text should be summarized?")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await SummarizeIntentHelper.performSummarization(
            model: model,
            text: text,
            directive: String(
                localized: "Summarize the following content into a concise paragraph that captures the main ideas. Reply with the summary only."
            )
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

struct SummarizeTextUsingListIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Summarize Text as List")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Summarize content into a list of key points."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should summarize the text?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What text should be summarized?")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Summarize as list \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await SummarizeIntentHelper.performSummarization(
            model: model,
            text: text,
            directive: String(
                localized: "Summarize the following content into a list of short bullet points that highlight the essential facts. Reply with the bullet list only."
            )
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

enum SummarizeIntentHelper {
    static func performSummarization(
        model: ShortcutsEntities.ModelEntity?,
        text: String,
        directive: String
    ) async throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShortcutError.emptyMessage }

        let message = [
            directive,
            "",
            "---",
            String(localized: "Source Text:"),
            trimmed,
        ].joined(separator: "\n")

        return try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: nil,
            options: .init(allowsImages: false)
        )
    }
}

import AppIntents
import Foundation

struct SummarizeTextIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Summarize Text"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Summarize content into a short paragraph."),
            categoryName: LocalizedStringResource("Writing Assistance"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What text should be summarized?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Summarize the provided text") {
                \.$model
                \.$text
            }
        } otherwise: {
            Summary("Summarize the provided text with the default model") {
                \.$model
                \.$text
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await TextTransformIntentHelper.perform(
            model: model,
            text: text,
            directive: String(
                localized: "Summarize the following content into a concise paragraph that captures the main ideas. Reply with the summary only.",
            ),
            sourceLabel: String(localized: "Source Text:"),
        )
    }
}

struct SummarizeTextUsingListIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Summarize Text as List"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Summarize content into a list of key points."),
            categoryName: LocalizedStringResource("Writing Assistance"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What text should be summarized?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("List the key points from the text") {
                \.$model
                \.$text
            }
        } otherwise: {
            Summary("List the key points using the default model") {
                \.$model
                \.$text
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await TextTransformIntentHelper.perform(
            model: model,
            text: text,
            directive: String(
                localized: "Summarize the following content into a list of short bullet points that highlight the essential facts. Reply with the bullet list only.",
            ),
            sourceLabel: String(localized: "Source Text:"),
        )
    }
}

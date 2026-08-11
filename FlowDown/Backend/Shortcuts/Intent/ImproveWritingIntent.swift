import AppIntents
import Foundation

struct ImproveWritingMoreProfessionalIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Improve Writing - Professional"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Rewrite text in a more professional tone while preserving meaning."),
            categoryName: LocalizedStringResource("Writing Assistance"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What text should be rewritten?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Rewrite the text with a professional tone") {
                \.$model
                \.$text
            }
        } otherwise: {
            Summary("Rewrite the text professionally using the default model") {
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
                localized: "Rewrite the following content so it reads professional, confident, and concise while preserving the original meaning. Reply with the revised text only.",
            ),
            sourceLabel: String(localized: "Original Text:"),
        )
    }
}

struct ImproveWritingMoreFriendlyIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Improve Writing - Friendly"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Rewrite text with a warmer and more approachable tone."),
            categoryName: LocalizedStringResource("Writing Assistance"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What text should be rewritten?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Rewrite the text with a friendly tone") {
                \.$model
                \.$text
            }
        } otherwise: {
            Summary("Rewrite the text in a friendly tone using the default model") {
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
                localized: "Rewrite the following content to sound warm, friendly, and easy to understand while keeping the same intent. Reply with the revised text only.",
            ),
            sourceLabel: String(localized: "Original Text:"),
        )
    }
}

struct ImproveWritingMoreConciseIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Improve Writing - Concise"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Trim text to be more concise without losing the key message."),
            categoryName: LocalizedStringResource("Writing Assistance"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What text should be rewritten?")
    var text: String

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Make the text more concise") {
                \.$model
                \.$text
            }
        } otherwise: {
            Summary("Make the text concise using the default model") {
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
                localized: "Rewrite the following content to be more concise and direct while keeping essential details. Reply with the revised text only.",
            ),
            sourceLabel: String(localized: "Original Text:"),
        )
    }
}

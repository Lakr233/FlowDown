import AppIntents
import Foundation

struct ImproveWritingMoreProfessionalIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Improve Writing - Professional")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Rewrite text in a more professional tone while preserving meaning."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should rewrite the text?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What text should be rewritten?")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite professionally \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await executeRewrite(
            directive: String(
                localized: "Rewrite the following content so it reads professional, confident, and concise while preserving the original meaning. Reply with the revised text only."
            )
        )
    }

    private func executeRewrite(directive: String) async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await ImproveWritingIntentHelper.performRewrite(
            model: model,
            text: text,
            directive: directive
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

struct ImproveWritingMoreFriendlyIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Improve Writing - Friendly")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Rewrite text with a warmer and more approachable tone."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should rewrite the text?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What text should be rewritten?")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite friendly \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await executeRewrite(
            directive: String(
                localized: "Rewrite the following content to sound warm, friendly, and easy to understand while keeping the same intent. Reply with the revised text only."
            )
        )
    }

    private func executeRewrite(directive: String) async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await ImproveWritingIntentHelper.performRewrite(
            model: model,
            text: text,
            directive: directive
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

struct ImproveWritingMoreConciseIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Improve Writing - Concise")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Trim text to be more concise without losing the key message."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should rewrite the text?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What text should be rewritten?")
    )
    var text: String

    static var parameterSummary: some ParameterSummary {
        Summary("Rewrite concise \(\.$text)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        try await executeRewrite(
            directive: String(
                localized: "Rewrite the following content to be more concise and direct while keeping essential details. Reply with the revised text only."
            )
        )
    }

    private func executeRewrite(directive: String) async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await ImproveWritingIntentHelper.performRewrite(
            model: model,
            text: text,
            directive: directive
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

enum ImproveWritingIntentHelper {
    static func performRewrite(
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
            String(localized: "Original Text:"),
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

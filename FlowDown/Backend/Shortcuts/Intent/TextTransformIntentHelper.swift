//
//  TextTransformIntentHelper.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import AppIntents
import Foundation

/// Shared body of every "run this directive over the user's text" shortcut.
/// The rewrite and summarize intents only differ in the directive and in how
/// the source block is labelled.
enum TextTransformIntentHelper {
    static func perform(
        model: ShortcutsEntities.ModelEntity?,
        text: String,
        directive: String,
        sourceLabel: String,
    ) async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ShortcutError.emptyMessage }

        let message = [
            directive,
            "",
            "---",
            sourceLabel,
            trimmed,
        ].joined(separator: "\n")

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: nil,
            audio: nil,
            options: .init(allowsImages: false),
        )
        return .result(value: response, dialog: IntentDialog(.init(stringLiteral: response)))
    }
}

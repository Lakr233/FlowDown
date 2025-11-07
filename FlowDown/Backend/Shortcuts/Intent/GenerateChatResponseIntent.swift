import AppIntents
import ChatClientKit
import Foundation
import UIKit
import UniformTypeIdentifiers

struct GenerateChatResponseIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Quick Reply")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Send a message and get the model's response."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should answer?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Message"),
        requestValueDialog: IntentDialog("What do you want to ask?")
    )
    var message: String

    @Parameter(
        title: LocalizedStringResource("Save to Conversation"),
        default: false
    )
    var saveToConversation: Bool

    @Parameter(
        title: LocalizedStringResource("Enable Memory"),
        default: false
    )
    var enableMemory: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Quick Reply") {
            \.$saveToConversation
            \.$enableMemory
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: nil,
            options: .init(
                allowsImages: false,
                saveToConversation: saveToConversation,
                enableMemory: enableMemory
            )
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

@available(iOS 18.0, macCatalyst 18.0, *)
struct GenerateChatResponseWithImagesIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Quick Reply with Image")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Send a message with an image and get the model's response."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Model"),
        requestValueDialog: IntentDialog("Which model should answer?")
    )
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(
        title: LocalizedStringResource("Message"),
        requestValueDialog: IntentDialog("What do you want to ask?")
    )
    var message: String

    @Parameter(
        title: LocalizedStringResource("Image"),
        supportedContentTypes: [.image],
        requestValueDialog: IntentDialog("Select an image to include.")
    )
    var image: IntentFile?

    @Parameter(
        title: LocalizedStringResource("Save to Conversation"),
        default: false
    )
    var saveToConversation: Bool

    @Parameter(
        title: LocalizedStringResource("Enable Memory"),
        default: false
    )
    var enableMemory: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Quick Reply with Image") {
            \.$saveToConversation
            \.$enableMemory
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: message,
            image: image,
            options: .init(
                allowsImages: true,
                saveToConversation: saveToConversation,
                enableMemory: enableMemory
            )
        )
        let dialog = IntentDialog(.init(stringLiteral: response))
        return .result(value: response, dialog: dialog)
    }
}

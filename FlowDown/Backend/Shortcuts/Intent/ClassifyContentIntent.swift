import AppIntents
import Foundation

struct ClassifyContentIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Classify Content")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Use the model to classify content into one of the provided candidates. If the model cannot decide, the first candidate is returned."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Prompt")
    )
    var prompt: String

    @Parameter(
        title: LocalizedStringResource("Content"),
        requestValueDialog: IntentDialog("What content should be classified?")
    )
    var content: String

    @Parameter(
        title: LocalizedStringResource("Candidates"),
        requestValueDialog: IntentDialog("Provide the candidate labels.")
    )
    var candidates: [String]

    static var parameterSummary: some ParameterSummary {
        Summary("Classify \(\.$content)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let request = try ClassificationPromptBuilder.make(
            prompt: prompt,
            content: content,
            candidates: candidates,
            requireContent: true,
            includeImageInstruction: false
        )

        let response = try await InferenceIntentHandler.execute(
            model: nil,
            message: request.message,
            image: nil,
            options: .init(allowsImages: false)
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

@available(iOS 18.0, macCatalyst 18.0, *)
struct ClassifyContentWithImageIntent: AppIntent {
    static var title: LocalizedStringResource {
        LocalizedStringResource("Classify Content with Image")
    }

    static var description = IntentDescription(
        LocalizedStringResource(
            "Use the model to classify content with the help of an accompanying image. If the model cannot decide, the first candidate is returned."
        )
    )

    @Parameter(
        title: LocalizedStringResource("Prompt")
    )
    var prompt: String

    @Parameter(
        title: LocalizedStringResource("Content"),
        default: "",
        requestValueDialog: IntentDialog("Add any additional details for the classification.")
    )
    var content: String

    @Parameter(
        title: LocalizedStringResource("Image"),
        supportedContentTypes: [.image],
        requestValueDialog: IntentDialog("Select an image to accompany the request.")
    )
    var image: IntentFile

    @Parameter(
        title: LocalizedStringResource("Candidates"),
        requestValueDialog: IntentDialog("Provide the candidate labels.")
    )
    var candidates: [String]

    static var parameterSummary: some ParameterSummary {
        Summary("Classify \(\.$image)") {
            \.$content
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let request = try ClassificationPromptBuilder.make(
            prompt: prompt,
            content: content,
            candidates: candidates,
            requireContent: false,
            includeImageInstruction: true
        )

        let response = try await InferenceIntentHandler.execute(
            model: nil,
            message: request.message,
            image: image,
            options: .init(allowsImages: true)
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

private enum ClassificationPromptBuilder {
    struct Request {
        let message: String
        let sanitizedCandidates: [String]
        let primaryCandidate: String

        func resolveCandidate(from response: String) -> String {
            let normalized = response
                .components(separatedBy: .newlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.init(charactersIn: "\"'")))
                ?? ""

            return sanitizedCandidates.first {
                $0.compare(normalized, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            } ?? primaryCandidate
        }
    }

    static func make(
        prompt: String,
        content: String,
        candidates: [String],
        requireContent: Bool,
        includeImageInstruction: Bool
    ) throws -> Request {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if requireContent, trimmedContent.isEmpty {
            throw ShortcutError.emptyMessage
        }

        let sanitizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let primaryCandidate = sanitizedCandidates.first else {
            throw ShortcutError.invalidCandidates
        }

        let candidateList = sanitizedCandidates.enumerated()
            .map { index, value in
                "\(index + 1). \(value)"
            }
            .joined(separator: "\n")

        let baseInstruction = String(
            localized: "You are a classification assistant. Choose the best candidate for the provided content."
        )

        let imageInstruction = String(
            localized: "An image is provided with this request. Consider the visual details when selecting the candidate."
        )

        let outputInstructionFormat = String(
            localized: "Respond with exactly one candidate string from the list above. If you are unsure, respond with '%@'."
        )
        let outputInstruction = String(format: outputInstructionFormat, primaryCandidate)

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)

        var instructionSegments: [String] = [baseInstruction]

        if includeImageInstruction {
            instructionSegments.append(imageInstruction)
        }

        if !trimmedPrompt.isEmpty {
            instructionSegments.append(trimmedPrompt)
        }

        instructionSegments.append(String(localized: "Candidates:"))
        instructionSegments.append(candidateList)

        if !trimmedContent.isEmpty {
            instructionSegments.append(String(localized: "Content:"))
            instructionSegments.append(trimmedContent)
        }

        instructionSegments.append(outputInstruction)

        let message = instructionSegments.joined(separator: "\n\n")

        return Request(
            message: message,
            sanitizedCandidates: sanitizedCandidates,
            primaryCandidate: primaryCandidate
        )
    }
}

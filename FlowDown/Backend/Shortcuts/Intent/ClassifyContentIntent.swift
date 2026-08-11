import AppIntents
import ChatClientKit
import Foundation

struct ClassifyContentIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Classify Content"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Use the model to classify content into one of the provided candidates. If the model cannot decide, the first candidate is returned."),
            categoryName: LocalizedStringResource("Classification"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Content", requestValueDialog: "What content should be classified?")
    var content: String

    @Parameter(title: "Candidate A", default: "")
    var candidateA: String

    @Parameter(title: "Candidate B", default: "")
    var candidateB: String

    @Parameter(title: "Candidate C", default: "")
    var candidateC: String

    @Parameter(title: "Candidate D", default: "")
    var candidateD: String

    private func makeManualCandidates() -> [String] {
        [
            candidateA,
            candidateB,
            candidateC,
            candidateD,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Use the selected model to classify your \(\.$content)") {
                \.$model
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        } otherwise: {
            Summary("Use the default model to classify your \(\.$content)") {
                \.$model
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw ShortcutError.emptyMessage
        }

        let resolvedCandidates = try CandidateInputResolver.resolveCandidates(
            manualCandidates: makeManualCandidates(),
        )

        let request = try ClassificationPromptBuilder.make(
            content: trimmedContent,
            candidates: resolvedCandidates,
            includeImageInstruction: false,
        )

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: request.message,
            image: nil,
            audio: nil,
            options: .init(allowsImages: false, forcedTool: request.tool),
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

@available(iOS 18.0, macCatalyst 18.0, *)
struct ClassifyContentWithImageIntent: AppIntent {
    static var title: LocalizedStringResource {
        "Classify Image"
    }

    static var description: IntentDescription {
        IntentDescription(
            LocalizedStringResource("Use the model to classify content with the help of an accompanying image. If the model cannot decide, the first candidate is returned."),
            categoryName: LocalizedStringResource("Classification"),
        )
    }

    @Parameter(title: "Model", default: nil)
    var model: ShortcutsEntities.ModelEntity?

    @Parameter(title: "Image", supportedContentTypes: [.image], requestValueDialog: "Select an image to accompany the request.")
    var image: IntentFile

    @Parameter(title: "Candidate A", default: "")
    var candidateA: String

    @Parameter(title: "Candidate B", default: "")
    var candidateB: String

    @Parameter(title: "Candidate C", default: "")
    var candidateC: String

    @Parameter(title: "Candidate D", default: "")
    var candidateD: String

    private func makeManualCandidates() -> [String] {
        [
            candidateA,
            candidateB,
            candidateC,
            candidateD,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    static var parameterSummary: some ParameterSummary {
        When(\.$model, .hasAnyValue) {
            Summary("Use the selected model to classify the image") {
                \.$model
                \.$image
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        } otherwise: {
            Summary("Use the default model to classify the image") {
                \.$model
                \.$image
                \.$candidateA
                \.$candidateB
                \.$candidateC
                \.$candidateD
            }
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let resolvedCandidates = try CandidateInputResolver.resolveCandidates(
            manualCandidates: makeManualCandidates(),
        )

        let request = try ClassificationPromptBuilder.make(
            content: nil,
            candidates: resolvedCandidates,
            includeImageInstruction: true,
        )

        let response = try await InferenceIntentHandler.execute(
            model: model,
            message: request.message,
            image: image,
            audio: nil,
            options: .init(allowsImages: true, forcedTool: request.tool),
        )

        let resolved = request.resolveCandidate(from: response)
        let dialog = IntentDialog(.init(stringLiteral: resolved))
        return .result(value: resolved, dialog: dialog)
    }
}

private enum ClassificationToolCall {
    static let name = "submit_classification"

    static func definition(candidates: [String]) -> ChatRequestBody.Tool {
        .function(
            name: name,
            description: "Report the candidate label that best matches the provided content.",
            parameters: [
                "type": "object",
                "properties": [
                    "label": [
                        "type": "string",
                        "enum": .array(candidates.map { .string($0) }),
                        "description": "The chosen candidate, exactly as listed.",
                    ],
                ],
                "required": ["label"],
                "additionalProperties": false,
            ],
            strict: true,
        )
    }

    struct Arguments: Decodable {
        let label: String?
    }
}

private enum ClassificationPromptBuilder {
    struct Request {
        let message: String
        let tool: ChatRequestBody.Tool
        let sanitizedCandidates: [String]
        let primaryCandidate: String

        /// `arguments` is the raw JSON of the forced tool call.
        func resolveCandidate(from arguments: String) -> String {
            guard let data = arguments.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(ClassificationToolCall.Arguments.self, from: data),
                  let label = decoded.label?.trimmingCharacters(in: .whitespacesAndNewlines)
            else {
                return primaryCandidate
            }

            return sanitizedCandidates.first {
                $0.compare(label, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
            } ?? primaryCandidate
        }
    }

    static func make(
        content: String?,
        candidates: [String],
        includeImageInstruction: Bool,
    ) throws -> Request {
        let trimmedContent = content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        let sanitizedCandidates = candidates
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard let primaryCandidate = sanitizedCandidates.first else {
            throw ShortcutError.invalidCandidates
        }

        var instructionSegments = [
            "You are a classification assistant. Choose the best candidate for the provided content and report it by calling \(ClassificationToolCall.name).",
        ]

        if includeImageInstruction {
            instructionSegments.append(
                "An image is provided with this request. Consider the visual details when selecting the candidate.",
            )
        }

        instructionSegments.append("Candidates:")
        instructionSegments.append(sanitizedCandidates.map { "- \($0)" }.joined(separator: "\n"))

        if !trimmedContent.isEmpty {
            instructionSegments.append("Content:")
            instructionSegments.append(trimmedContent)
        }

        instructionSegments.append(
            "If you are unsure, choose \(primaryCandidate).",
        )

        let message = instructionSegments.joined(separator: "\n\n")

        return Request(
            message: message,
            tool: ClassificationToolCall.definition(candidates: sanitizedCandidates),
            sanitizedCandidates: sanitizedCandidates,
            primaryCandidate: primaryCandidate,
        )
    }
}

private enum CandidateInputResolver {
    static func resolveCandidates(
        manualCandidates: [String],
    ) throws -> [String] {
        var ordered: [String] = []
        var seen: Set<String> = []

        func append(_ candidate: String) {
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let normalized = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            guard seen.insert(normalized).inserted else { return }
            ordered.append(trimmed)
        }

        manualCandidates.forEach(append)

        guard !ordered.isEmpty else {
            throw ShortcutError.invalidCandidates
        }

        return ordered
    }
}

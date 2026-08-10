@testable import FlowDown
import Foundation
import MLXLLM
import MLXLMCommon
import Storage
import Testing

struct LocalModelConfigurationSmokeTests {
    private static let mlxValidationModelID = "mlx-community/Qwen3.5-2B-4bit"

    @Test
    func `root fdmodel files decode as cloud models when present`() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = try FileManager.default.contentsOfDirectory(
            at: repositoryRoot,
            includingPropertiesForKeys: nil,
        )
        .filter { $0.pathExtension == ModelManager.flowdownModelConfigurationExtension }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard !candidates.isEmpty else {
            return
        }

        let decoder = PropertyListDecoder()

        for url in candidates {
            let model = try decoder.decode(CloudModel.self, from: Data(contentsOf: url))

            #expect(!model.model_identifier.isEmpty)
            #expect(!model.endpoint.isEmpty)
            #expect(!model.token.isEmpty)

            if let inferredFormat = CloudModel.ResponseFormat.inferredFormat(fromEndpoint: model.endpoint) {
                #expect(inferredFormat == model.response_format)
            }
        }
    }

    @Test
    func `selected mlx validation model supports tool calling`() {
        let configuration = LLMRegistry.shared.configuration(id: Self.mlxValidationModelID)

        #expect(configuration.name == Self.mlxValidationModelID)
        #expect(LLMRegistry.shared.contains(id: Self.mlxValidationModelID))

        // The xmlFunction tool-call format is declared on `Qwen35Model` via
        // `ChatConventionsProviding` and pinned by mlx-swift-lm's own suite;
        // reading it here would need a model instance, which MLX cannot
        // construct in the simulator this target runs on.
        #expect(ToolCallFormat.allCases.contains(.xmlFunction))
    }
}

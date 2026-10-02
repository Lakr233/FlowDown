import Combine
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ModelManagerLocalTests {
    @Test
    func `local model metadata helpers expose display name scope and tags`() {
        let model = LocalModel(
            id: "local-model",
            model_identifier: "mlx-community/Qwen2-7B-Instruct",
            downloaded: Date(timeIntervalSince1970: 1_700_000_000),
            size: 0,
            capabilities: [.visual, .tool],
            context: .medium_64k,
        )

        #expect(model.modelDisplayName == "Qwen2-7B-Instruct")
        #expect(model.scopeIdentifier == "mlx-community")
        #expect(model.auxiliaryIdentifier == "@localhost@mlx-community")
        #expect(model.tags.contains("@localhost@mlx-community"))
        #expect(model.capabilities.contains(.visual))
        #expect(model.capabilities.contains(.tool))
    }

    @Test
    func `scanLocalModels removes invalid directories unknown files and hacked manifests`() throws {
        try withTemporaryModelManager { manager in
            let validModel = LocalModel(
                id: "valid-model",
                model_identifier: "mlx-community/valid",
                downloaded: .now,
                size: 0,
                capabilities: [.tool],
            )
            let validDirectory = try writeLocalModel(validModel, into: manager.localModelDir)
            let unknownItem = validDirectory.appendingPathComponent("unknown.txt")
            try Data("junk".utf8).write(to: unknownItem, options: .atomic)

            let invalidDirectory = manager.localModelDir.appendingPathComponent("missing-manifest")
            try FileManager.default.createDirectory(at: invalidDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(
                at: invalidDirectory.appendingPathComponent("content"),
                withIntermediateDirectories: true,
            )

            let hackedModel = LocalModel(
                id: "manifest-id",
                model_identifier: "mlx-community/hacked",
                downloaded: .now,
                size: 0,
                capabilities: [],
            )
            _ = try writeLocalModel(hackedModel, into: manager.localModelDir, directoryName: "wrong-directory")

            let scanned = manager.scanLocalModels()

            #expect(scanned.map(\.id) == [validModel.id])
            #expect(!FileManager.default.fileExists(atPath: unknownItem.path))
            #expect(!FileManager.default.fileExists(atPath: invalidDirectory.path))
            #expect(!FileManager.default.fileExists(
                atPath: manager.localModelDir.appendingPathComponent("wrong-directory").path,
            ))
        }
    }

    @Test
    func `tempDirForDownloadLocalModel is stable for the same identifier`() throws {
        try withTemporaryModelManager { manager in
            let first = manager.tempDirForDownloadLocalModel(model_identifier: "mlx-community/Qwen2-7B")
            let second = manager.tempDirForDownloadLocalModel(model_identifier: "mlx-community/Qwen2-7B")
            let third = manager.tempDirForDownloadLocalModel(model_identifier: "mlx-community/Other")

            #expect(first == second)
            #expect(first != third)
        }
    }

    @Test
    func `calibrateLocalModelSize and editLocalModel persist manifest updates`() throws {
        try withTemporaryModelManager { manager in
            let model = LocalModel(
                id: "size-model",
                model_identifier: "mlx-community/sized",
                downloaded: .now,
                size: 0,
                capabilities: [.visual],
            )
            let modelDirectory = try writeLocalModel(
                model,
                into: manager.localModelDir,
                contentFiles: [
                    "weights.bin": Data(repeating: 0x01, count: 5),
                    "config.json": Data(repeating: 0x02, count: 7),
                ],
            )

            manager.localModels.send(manager.scanLocalModels())
            let size = manager.calibrateLocalModelSize(identifier: model.id)
            manager.editLocalModel(identifier: model.id) {
                $0.temperature_preference = .custom
            }

            let manifestURL = modelDirectory
                .appendingPathComponent("manifest")
                .appendingPathComponent("info")
                .appendingPathExtension("plist")
            let persisted = try PropertyListDecoder().decode(LocalModel.self, from: Data(contentsOf: manifestURL))

            #expect(size == 12)
            #expect(persisted.size == 12)
            #expect(persisted.temperature_preference == .custom)
        }
    }

    @Test
    func `pack and unpackAndImport round trip a local model between isolated managers`() async throws {
        try await withTemporaryModelManager { sourceManager in
            let sourceModel = LocalModel(
                id: "roundtrip-model",
                model_identifier: "mlx-community/roundtrip",
                downloaded: .now,
                size: 0,
                capabilities: [.tool, .visual],
            )
            _ = try writeLocalModel(
                sourceModel,
                into: sourceManager.localModelDir,
                contentFiles: [
                    "weights.bin": Data(repeating: 0x03, count: 9),
                ],
            )
            sourceManager.localModels.send(sourceManager.scanLocalModels())

            let packed: (URL, () -> Void) = try await withCheckedThrowingContinuation { continuation in
                sourceManager.pack(model: sourceModel) { url, cleanup in
                    guard let url else {
                        cleanup()
                        continuation.resume(throwing: NSError(domain: "ModelManagerLocalTests", code: 1))
                        return
                    }
                    continuation.resume(returning: (url, cleanup))
                }
            }
            defer { packed.1() }

            try await withTemporaryModelManager { importManager in
                let result: Result<LocalModel, Error> = await withCheckedContinuation { continuation in
                    DispatchQueue.global(qos: .userInitiated).async {
                        continuation.resume(returning: importManager.unpackAndImport(modelAt: packed.0))
                    }
                }
                let imported: LocalModel
                switch result {
                case let .success(model):
                    imported = model
                case let .failure(error):
                    throw error
                }
                let importedContent = importManager
                    .dirForLocalModel(identifier: imported.id)
                    .appendingPathComponent("content")
                    .appendingPathComponent("weights.bin")

                #expect(imported.id == sourceModel.id)
                #expect(imported.model_identifier == sourceModel.model_identifier)
                #expect(FileManager.default.fileExists(atPath: importedContent.path))
                #expect(importManager.localModel(identifier: imported.id)?.model_identifier == sourceModel.model_identifier)
            }
        }
    }
}

private extension ModelManagerLocalTests {
    func withTemporaryModelManager(
        _ body: (ModelManager) throws -> Void,
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerLocalTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDir = root.appendingPathComponent("Models.Local", isDirectory: true)
        let downloadDir = root.appendingPathComponent("Models.Local.Temp", isDirectory: true)

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let manager = ModelManager(
            localModelDir: modelDir,
            localModelDownloadTempDir: downloadDir,
        )
        manager.gpuSupportProvider = { true }

        do {
            try body(manager)
            try? FileManager.default.removeItem(at: root)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func withTemporaryModelManager(
        _ body: (ModelManager) async throws -> Void,
    ) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerLocalTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDir = root.appendingPathComponent("Models.Local", isDirectory: true)
        let downloadDir = root.appendingPathComponent("Models.Local.Temp", isDirectory: true)

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let manager = ModelManager(
            localModelDir: modelDir,
            localModelDownloadTempDir: downloadDir,
        )
        manager.gpuSupportProvider = { true }

        do {
            try await body(manager)
            try? FileManager.default.removeItem(at: root)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func withTemporaryModelManager<T>(
        _ body: (ModelManager) async throws -> T,
    ) async throws -> T {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerLocalTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let modelDir = root.appendingPathComponent("Models.Local", isDirectory: true)
        let downloadDir = root.appendingPathComponent("Models.Local.Temp", isDirectory: true)

        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let manager = ModelManager(
            localModelDir: modelDir,
            localModelDownloadTempDir: downloadDir,
        )
        manager.gpuSupportProvider = { true }

        do {
            let result = try await body(manager)
            try? FileManager.default.removeItem(at: root)
            return result
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    func writeLocalModel(
        _ model: LocalModel,
        into modelsDirectory: URL,
        directoryName: String? = nil,
        contentFiles: [String: Data] = ["weights.bin": Data(repeating: 0x00, count: 4)],
    ) throws -> URL {
        let modelDirectory = modelsDirectory.appendingPathComponent(directoryName ?? model.id, isDirectory: true)
        let manifestDirectory = modelDirectory.appendingPathComponent("manifest", isDirectory: true)
        let contentDirectory = modelDirectory.appendingPathComponent("content", isDirectory: true)

        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)

        let manifestURL = manifestDirectory
            .appendingPathComponent("info")
            .appendingPathExtension("plist")
        let manifestData = try PropertyListEncoder().encode(model)
        try manifestData.write(to: manifestURL, options: .atomic)

        for (name, data) in contentFiles {
            try data.write(to: contentDirectory.appendingPathComponent(name), options: .atomic)
        }

        return modelDirectory
    }
}

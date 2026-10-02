import Combine
@preconcurrency @testable import FlowDown
import Foundation
import Storage
import Testing

@Suite(.serialized)
struct ModelManagerLocalImportTests {
    @Test(arguments: ["../victim", "..", "."])
    func unpackAndImportTraversalIdentifier_rejectsWithoutDeletingOutsideFiles(craftedID: String) async throws {
        try await FlowDownTestContext.shared.ensureBootstrappedEnvironment()

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelManagerLocalImportTests")
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let sourceManager = try makeManager(at: root.appendingPathComponent("source", isDirectory: true))
        let importManager = try makeManager(at: root.appendingPathComponent("import", isDirectory: true))

        // A sibling of Models.Local, standing in for Documents/Objects.db.
        let victimDirectory = importManager.localModelDir
            .deletingLastPathComponent()
            .appendingPathComponent("victim", isDirectory: true)
        try FileManager.default.createDirectory(at: victimDirectory, withIntermediateDirectories: true)
        let victimFile = victimDirectory.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: victimFile, options: .atomic)

        let installed = LocalModel(
            id: "installed-model",
            model_identifier: "mlx-community/installed",
            downloaded: .now,
            size: 0,
            capabilities: [],
        )
        let installedDirectory = try writeLocalModel(installed, into: importManager.localModelDir)
        importManager.localModels.send(importManager.scanLocalModels())

        let crafted = LocalModel(
            id: craftedID,
            model_identifier: "mlx-community/crafted",
            downloaded: .now,
            size: 0,
            capabilities: [],
        )
        _ = try writeLocalModel(crafted, into: sourceManager.localModelDir, directoryName: "crafted-package")
        let archive = try await pack(
            directoryNamed: "crafted-package",
            modelIdentifier: crafted.model_identifier,
            with: sourceManager,
        )
        defer { archive.cleanUp() }

        let result: Result<LocalModel, Error> = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: importManager.unpackAndImport(modelAt: archive.url))
            }
        }

        switch result {
        case .success:
            Issue.record("Expected a package with id \(craftedID) to be rejected.")
        case .failure:
            break
        }
        #expect(FileManager.default.fileExists(atPath: victimFile.path))
        #expect(FileManager.default.fileExists(
            atPath: installedDirectory
                .appendingPathComponent("content")
                .appendingPathComponent("weights.bin")
                .path,
        ))
    }
}

private extension ModelManagerLocalImportTests {
    func makeManager(at base: URL) throws -> ModelManager {
        let modelDir = base.appendingPathComponent("Models.Local", isDirectory: true)
        let downloadDir = base.appendingPathComponent("Models.Local.Temp", isDirectory: true)
        try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: downloadDir, withIntermediateDirectories: true)

        let manager = ModelManager(
            localModelDir: modelDir,
            localModelDownloadTempDir: downloadDir,
        )
        manager.gpuSupportProvider = { true }
        return manager
    }

    /// Zips a model directory as written on disk. `pack` only uses the id to
    /// find the directory, so the manifest inside keeps the crafted id.
    func pack(
        directoryNamed directoryName: String,
        modelIdentifier: String,
        with manager: ModelManager,
    ) async throws -> (url: URL, cleanUp: () -> Void) {
        let locator = LocalModel(
            id: directoryName,
            model_identifier: modelIdentifier,
            downloaded: .now,
            size: 0,
            capabilities: [],
        )
        return try await withCheckedThrowingContinuation { continuation in
            manager.pack(model: locator) { url, cleanUp in
                guard let url else {
                    cleanUp()
                    continuation.resume(throwing: NSError(domain: "ModelManagerLocalImportTests", code: 1))
                    return
                }
                continuation.resume(returning: (url, cleanUp))
            }
        }
    }

    func writeLocalModel(
        _ model: LocalModel,
        into modelsDirectory: URL,
        directoryName: String? = nil,
    ) throws -> URL {
        let modelDirectory = modelsDirectory.appendingPathComponent(directoryName ?? model.id, isDirectory: true)
        let manifestDirectory = modelDirectory.appendingPathComponent("manifest", isDirectory: true)
        let contentDirectory = modelDirectory.appendingPathComponent("content", isDirectory: true)

        try FileManager.default.createDirectory(at: manifestDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: contentDirectory, withIntermediateDirectories: true)

        let manifestURL = manifestDirectory
            .appendingPathComponent("info")
            .appendingPathExtension("plist")
        try PropertyListEncoder().encode(model).write(to: manifestURL, options: .atomic)
        try Data(repeating: 0x00, count: 4).write(
            to: contentDirectory.appendingPathComponent("weights.bin"),
            options: .atomic,
        )

        return modelDirectory
    }
}

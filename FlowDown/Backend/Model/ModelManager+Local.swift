//
//  ModelManager+Local.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import Combine
import CryptoKit
import Digger
import Foundation
import MLX
import Storage
import ZIPFoundation

/*

 Model is stored in the following structure:

 - Models.Local
   - id
     - manifest
       - info.plist
     - content
       - <subfiles>

 Files outside these scope are removed once scanned.

 */

extension ModelCapabilities {
    var icon: String {
        switch self {
        case .visual: "eye"
        case .tool: "hammer"
        case .developerRole: "person.crop.circle.badge.checkmark"
        case .auditory: "waveform"
        case .preservedThinking: "brain"
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .visual: "Visual"
        case .auditory: "Audio"
        case .tool: "Tool"
        case .developerRole: "Role"
        case .preservedThinking: "Contemplation"
        }
    }

    var description: String.LocalizationValue {
        switch self {
        case .visual: "Visual models can extract information from images."
        case .tool: "Specially trained models can use tools to read and write accurate information and automatically perform multi-turn processing."
        case .developerRole: "Specially trained models can use roles to distinguish the priority and importance of instructions. Some models require this feature."
        case .auditory: "Audio models can listen to sounds in attachments."
        case .preservedThinking: "Thinking models of this kind require the original reasoning of every turn to be preserved. When enabled, previous thinking is sent back to the model as reasoning content during inference. Some models require this feature."
        }
    }
}

extension LocalModel {
    var modelDisplayName: String {
        scopelessModelName
    }

    var repoIdentifier: String {
        model_identifier
    }
}

extension ModelManager {
    func scanLocalModels() -> [LocalModel] {
        guard gpuSupportProvider() else { return [] }

        let contents = try? FileManager.default.contentsOfDirectory(
            at: localModelDir,
            includingPropertiesForKeys: nil,
            options: [],
        )
        var ans = [LocalModel]()
        for content in contents ?? [] {
            let url = localModelDir.appendingPathComponent(content.lastPathComponent)
            let manifest = url
                .appendingPathComponent("manifest")
                .appendingPathComponent("info")
                .appendingPathExtension("plist")
            guard FileManager.default.fileExists(atPath: manifest.path),
                  let data = try? Data(contentsOf: manifest),
                  var model = try? decoder.decode(LocalModel.self, from: data),
                  FileManager.default.fileExists(atPath: self.modelContent(for: model).path),
                  dirForLocalModel(identifier: model.id) == url // otherwise it's a hacked model
            else {
                Logger.model.errorFile("removing invalid model: \(url)")
                try? FileManager.default.removeItem(at: url)
                continue
            }

            if model.id.isEmpty { model.id = UUID().uuidString }
            ans.append(model)

            let dirContent = try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [],
            )
            for item in dirContent ?? [] {
                if item.lastPathComponent == "manifest" || item.lastPathComponent == "content" { continue }
                Logger.model.errorFile("removing unknown item: \(item)")
                try? FileManager.default.removeItem(at: item)
            }
        }
        Logger.model.infoFile("scanned \(ans.count) local models")
        return ans.sorted(by: \.id)
    }

    func dirForLocalModel(identifier mid: LocalModelIdentifier) -> URL {
        localModelDir.appendingPathComponent(mid)
    }

    /// the name of the model, as id from hub
    func tempDirForDownloadLocalModel(model_identifier: String) -> URL {
        func hash(identifier mid: String) -> String {
            let data = Data(mid.utf8)
            let hash = Insecure.SHA1.hash(data: data)
            return hash.map { String(format: "%02hhx", $0) }.joined()
        }
        return localModelDownloadTempDir.appendingPathComponent(hash(identifier: model_identifier))
    }

    func localModel(identifier mid: LocalModelIdentifier) -> LocalModel? {
        localModels.value.first { $0.id.lowercased() == mid.lowercased() }
    }

    func calibrateLocalModelSize(identifier: LocalModelIdentifier) -> Int64 {
        guard let model = localModel(identifier: identifier) else { return 0 }
        let contentDir = modelContent(for: model)
        var size: Int64 = 0
        let keys: [URLResourceKey] = [.fileSizeKey, .isDirectoryKey]
        let contents = FileManager.default.enumerator(at: contentDir, includingPropertiesForKeys: keys)
        for case let fileURL as URL in contents ?? NSEnumerator() {
            do {
                let values = try fileURL.resourceValues(forKeys: Set(keys))
                if values.isDirectory != true {
                    size += Int64(values.fileSize ?? 0)
                }
            } catch {
                Logger.model.errorFile("error getting size for \(fileURL): \(error)")
                continue
            }
        }
        editLocalModel(identifier: identifier) {
            $0.size = .init(size)
        }
        return size
    }

    func editLocalModel(identifier mid: LocalModelIdentifier, block: @escaping (inout LocalModel) -> Void) {
        guard var model = localModel(identifier: mid) else { return }
        block(&model)
        let url = dirForLocalModel(identifier: mid)
        let manifest = url
            .appendingPathComponent("manifest")
            .appendingPathComponent("info")
            .appendingPathExtension("plist")
        try? encoder.encode(model).write(to: manifest)
        localModels.send(scanLocalModels())
    }

    /// HuggingFace Identifier, eg: mlx-community/Qwen2-VL-7B-Instruct-4bit
    func localModelExists(repoIdentifier: String) -> Bool {
        localModels.value.contains {
            $0.repoIdentifier.lowercased() == repoIdentifier.lowercased()
        }
    }

    func removeLocalModel(identifier mid: LocalModelIdentifier) {
        let url = dirForLocalModel(identifier: mid)
        try? FileManager.default.removeItem(at: url)
        localModels.send(scanLocalModels())
    }

    func modelContent(for model: LocalModel) -> URL {
        dirForLocalModel(identifier: model.id).appendingPathComponent("content")
    }

    func pack(
        model: LocalModel,
        progress: Progress? = nil,
        completion: @escaping (URL?, _ cleanUpBlock: @escaping () -> Void) -> Void,
    ) {
        let url = dirForLocalModel(identifier: model.id)
        let item = model.model_identifier
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .sanitizedFileName
        let tempDir = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("DisposeableResources")
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        let cleanUpBlock: () -> Void = { try? FileManager.default.removeItem(at: tempDir) }
        let zipFile = tempDir.appendingPathComponent(item).appendingPathExtension("zip")
        Task.detached {
            do {
                try FileManager.default.zipItem(
                    at: url,
                    to: zipFile,
                    shouldKeepParent: false,
                    compressionMethod: .none,
                    progress: progress,
                )
                completion(zipFile, cleanUpBlock)
            } catch {
                completion(nil, cleanUpBlock)
            }
        }
    }

    func unpackAndImport(modelAt url: URL) -> Result<LocalModel, Error> {
        assert(!Thread.isMainThread)
        guard gpuSupportProvider() else {
            return .failure(NSError(domain: "MLX", code: 2, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Your device does not support MLX."),
            ]))
        }
        let tempDir = disposableResourcesDir
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true, attributes: nil)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let zipFile = tempDir.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: url, to: zipFile)
            try FileManager.default.unzipItem(at: zipFile, to: tempDir)
            let manifest = tempDir
                .appendingPathComponent("manifest")
                .appendingPathComponent("info")
                .appendingPathExtension("plist")
            guard FileManager.default.fileExists(atPath: manifest.path),
                  let data = try? Data(contentsOf: manifest),
                  let model = try? decoder.decode(LocalModel.self, from: data)
            else {
                throw NSError(domain: "ModelManager", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: String(localized: "Invalid model file."),
                ])
            }
            if model.id.isEmpty {
                throw NSError(
                    domain: "Model",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "Invalid model identifier.")],
                )
            }
            let target = dirForLocalModel(identifier: model.id)
            try? FileManager.default.removeItem(at: target)
            try FileManager.default.moveItem(at: tempDir, to: target)
            localModels.send(scanLocalModels())
            return .success(model)
        } catch {
            return .failure(error)
        }
    }
}

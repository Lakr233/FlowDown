//
//  ModelManager+Hub.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/27/25.
//

import Combine
import CryptoKit
import Digger
import Foundation
import os
import Storage

private let huggingFaceAPI = HuggingFaceAPI()

struct HuggingFaceRepository {
    let id: String
}

struct HuggingFaceRepositoryFile: Decodable {
    let type: String
    let size: UInt64?
    let path: String

    var isFile: Bool {
        type == "file"
    }
}

enum HuggingFaceAPIError: LocalizedError {
    case invalidRepositoryIdentifier(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .invalidRepositoryIdentifier(identifier):
            "Invalid Hugging Face repository identifier: \(identifier)"
        case .invalidResponse:
            "Hugging Face returned an invalid response."
        }
    }
}

struct HuggingFaceAPI {
    func getFiles(from repository: HuggingFaceRepository) async throws -> [HuggingFaceRepositoryFile] {
        let identifier = repository.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
        guard let identifier else {
            throw HuggingFaceAPIError.invalidRepositoryIdentifier(repository.id)
        }
        guard let url = URL(string: "https://huggingface.co/api/models/\(identifier)/tree/main?recursive=1") else {
            throw HuggingFaceAPIError.invalidRepositoryIdentifier(repository.id)
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let response = response as? HTTPURLResponse, (200 ..< 300).contains(response.statusCode) else {
            throw HuggingFaceAPIError.invalidResponse
        }
        return try decodeFiles(from: data)
    }

    func decodeFiles(from data: Data) throws -> [HuggingFaceRepositoryFile] {
        let entries = try JSONDecoder().decode([HuggingFaceRepositoryFile].self, from: data)
        return entries.filter(\.isFile)
    }

    func totalSize(of files: [HuggingFaceRepositoryFile]) -> UInt64 {
        files.reduce(into: UInt64(0)) { partialResult, file in
            partialResult += file.size ?? 0
        }
    }
}

extension ModelManager {
    class HubDownloadProgress: ObservableObject, Equatable, Hashable {
        @Published var overall: Progress = .init(totalUnitCount: 100)
        @Published var currentFilename: String = .init(localized: "Sending Hello...")
        @Published var error: Error? = nil
        @Published var speed: String = ""
        @Published var cancellable: Bool = false

        var isCancelled: Bool = false {
            didSet {
                assert(isCancelled)
                cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
            }
        }

        var progressMap: [String: Progress] = [:] {
            didSet { updateOverallProgress() }
        }

        var cancellables: [URL] = []

        func catchError(_ error: Error) {
            Task { @MainActor in
                self.error = error
            }
        }

        func acquiredFileList(_ list: [String]) {
            progressMap.removeAll()
            for file in list {
                let progress = Progress()
                progress.totalUnitCount = 100
                progress.completedUnitCount = 0
                progressMap[file] = progress
            }
        }

        func progressOnFile(_ name: String, progress: Progress) {
            if progress.totalUnitCount <= 0 { return }
            Task { @MainActor in
                self.currentFilename = name
                self.progressMap[name] = progress
            }
        }

        func speedUpdate(speed: Int64) {
            let text = ByteCountFormatter.string(fromByteCount: speed, countStyle: .file)
            Task { @MainActor in
                self.speed = String(format: "%@/s", text)
            }
        }

        func completeFile(_ name: String, size: Int64) {
            let progress = progressMap[name, default: .init()]
            progress.totalUnitCount = size
            progress.completedUnitCount = size
            progressMap[name] = progress
        }

        func finalizeDownload() {
            for (name, progress) in progressMap {
                progress.completedUnitCount = progress.totalUnitCount
                progressMap[name] = progress
            }
        }

        func updateOverallProgress() {
            if progressMap.isEmpty { return }
            let totalCompleted = progressMap.values.reduce(0) { $0 + $1.completedUnitCount }
            let totalUnit = progressMap.values.reduce(0) { $0 + $1.totalUnitCount }
            let newOverall = Progress()
            newOverall.completedUnitCount = totalCompleted
            newOverall.totalUnitCount = totalUnit
            if newOverall.totalUnitCount <= 0 { return }
            Task { @MainActor in
                self.overall = newOverall
            }
        }

        func saveCancellableURL(_ url: URL) {
            cancellables.append(url)
        }

        func checkContinue() throws {
            guard isCancelled else { return }
            throw NSError(domain: "Downloader", code: 0, userInfo: [
                NSLocalizedDescriptionKey: String(localized: "Operation Cancelled"),
            ])
        }

        func onInterfaceDisappear() {
            cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
            Task { [weak progress = self] in
                try? await Task.sleep(for: .seconds(0.5))
                await MainActor.run { [weak progress] in
                    guard let progress else { return }
                    progress.isCancelled = true
                    progress.cancellables.forEach { DiggerManager.shared.cancelTask(for: $0) }
                }
            }
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(overall)
            hasher.combine(currentFilename)
            hasher.combine(error?.localizedDescription)
            hasher.combine(speed)
            hasher.combine(cancellable)
        }

        static func == (lhs: ModelManager.HubDownloadProgress, rhs: ModelManager.HubDownloadProgress) -> Bool {
            lhs.hashValue == rhs.hashValue
        }
    }
}

extension ModelManager {
    func checkModelSizeFromHugginFace(identifier: String) async throws -> UInt64 {
        let repo = HuggingFaceRepository(id: identifier)
        let files = try await huggingFaceAPI.getFiles(from: repo)
        return huggingFaceAPI.totalSize(of: files)
    }

    @discardableResult
    func downloadModelFromHuggingFace(
        identifier: String,
        populateProgressTo progress: HubDownloadProgress,
    ) async throws -> LocalModel {
        assert(!Thread.isMainThread)

        let repo = HuggingFaceRepository(id: identifier)

        // prepare temp directories structure
        let modelTempDir = tempDirForDownloadLocalModel(model_identifier: identifier)
        Logger.model.infoFile("preparing temp directory for \(identifier)...")
        let manifestDir = modelTempDir.appendingPathComponent("manifest")
        let contentDir = modelTempDir.appendingPathComponent("content")
        try? FileManager.default.createDirectory(
            at: manifestDir,
            withIntermediateDirectories: true,
            attributes: nil,
        )
        try? FileManager.default.createDirectory(
            at: contentDir,
            withIntermediateDirectories: true,
            attributes: nil,
        )

        Logger.model.infoFile("downloading manifest for \(identifier)...")

        let files = try await huggingFaceAPI.getFiles(from: repo)
        progress.acquiredFileList(files.map(\.path))

        await MainActor.run { progress.cancellable = true }

        for file in files {
            try progress.checkContinue()
            progress.progressOnFile(file.path, progress: .init(totalUnitCount: Int64(file.size ?? 0)))
        }

        for file in files {
            try progress.checkContinue()

            let filename = file.path
            let dest = contentDir.appendingPathComponent(filename)
            defer {
                let size = (try? FileManager.default.attributesOfItem(atPath: dest.path)[.size] as? Int64) ?? 0
                progress.completeFile(filename, size: size)
            }
            if FileManager.default.fileExists(atPath: dest.path) {
                Logger.model.debugFile("skipping \(filename) for \(identifier)")
                continue
            }

            Logger.model.infoFile("downloading \(filename) for \(identifier)")
            let remoteURL = URL(string: "https://huggingface.co")!
                .appendingPathComponent(repo.id)
                .appendingPathComponent("resolve")
                .appendingPathComponent("main")
                .appendingPathComponent(filename)

            var i = 0
            var capturedError: Error?
            while i < 5 {
                try progress.checkContinue()
                struct DownloadAttemptState {
                    var didResumeContinuation = false
                    var hasMadeProgress = false
                }
                let attemptState = OSAllocatedUnfairLock(initialState: DownloadAttemptState())
                do {
                    let result: URL = try await withUnsafeThrowingContinuation { cont in
                        DiggerManager.shared.download(with: remoteURL)
                            .progress {
                                progress.progressOnFile(filename, progress: $0)
                                attemptState.withLock { state in
                                    state.hasMadeProgress = true
                                }
                            }
                            .speed { progress.speedUpdate(speed: $0) }
                            .completion { completion in
                                let shouldResume = attemptState.withLock { state in
                                    guard !state.didResumeContinuation else { return false }
                                    state.didResumeContinuation = true
                                    return true
                                }
                                guard shouldResume else { return }
                                switch completion {
                                case let .failure(error): cont.resume(throwing: error)
                                case let .success(url): cont.resume(returning: url)
                                }
                            }
                        progress.saveCancellableURL(remoteURL)
                    }
                    try progress.checkContinue()
                    try? FileManager.default.createDirectory(
                        at: dest.deletingLastPathComponent(),
                        withIntermediateDirectories: true,
                        attributes: nil,
                    )
                    try FileManager.default.moveItem(at: result, to: dest)
                    capturedError = nil
                    break
                } catch {
                    capturedError = error
                    let someProgressHasBeenMade = attemptState.withLock { state in
                        state.hasMadeProgress
                    }
                    if !someProgressHasBeenMade { i += 1 }
                    sleep(3)
                    continue
                }
            }
            if let error = capturedError {
                progress.catchError(error)
                throw error
            }
        }

        await MainActor.run { progress.cancellable = false }
        try progress.checkContinue()

        Logger.model.infoFile("download completed for \(identifier), finalizing...")

        progress.finalizeDownload()

        var size: UInt64 = 0
        for content in try FileManager.default.contentsOfDirectory(atPath: contentDir.path) {
            let url = contentDir.appendingPathComponent(content)
            try size += (FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        }
        Logger.model.infoFile("total size for \(identifier): \(size)")

        // prepare model/manifest directory
        let model = LocalModel(
            model_identifier: identifier,
            downloaded: .init(),
            size: size,
            capabilities: [],
        )
        let manifest = manifestDir
            .appendingPathComponent("info")
            .appendingPathExtension("plist")
        try? FileManager.default.removeItem(at: manifest)
        try encoder.encode(model).write(to: manifest)

        // move both directories to final destination
        let modelDir = dirForLocalModel(identifier: model.id)
        Logger.model.infoFile("moving model \(identifier) to final dest \(modelDir)")
        try? FileManager.default.removeItem(at: modelDir)
        try? FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true, attributes: nil)
        try FileManager.default.moveItem(
            at: contentDir,
            to: modelDir.appendingPathComponent(contentDir.lastPathComponent)
        )
        try FileManager.default.moveItem(
            at: manifestDir,
            to: modelDir.appendingPathComponent(manifestDir.lastPathComponent)
        )

        let models = scanLocalModels()
        localModels.send(models)

        return model
    }
}

@preconcurrency import AVFoundation
import CoreMedia
import Foundation
import UniformTypeIdentifiers

enum AudioTranscoderError: Error {
    case assetNotSupported
    case exportFailed(String)
    case readerWriterFailed(String)
}

enum AudioTranscoder {
    enum OutputFormat {
        case mediumQualityM4A
        case compressedQualityWAV

        var fileType: AVFileType {
            switch self {
            case .mediumQualityM4A:
                .m4a
            case .compressedQualityWAV:
                .wav
            }
        }

        var fileExtension: String {
            switch self {
            case .mediumQualityM4A:
                "m4a"
            case .compressedQualityWAV:
                "wav"
            }
        }

        var preferredExportPresets: [String] {
            switch self {
            case .mediumQualityM4A:
                [
                    AVAssetExportPresetAppleM4A,
                    AVAssetExportPresetMediumQuality,
                    AVAssetExportPresetPassthrough,
                ]
            case .compressedQualityWAV:
                [
                    AVAssetExportPresetPassthrough,
                    AVAssetExportPresetMediumQuality,
                ]
            }
        }

        var optimizeForNetworkUse: Bool {
            switch self {
            case .mediumQualityM4A:
                true
            case .compressedQualityWAV:
                false
            }
        }

        func readerOutputSettings(sampleRate: Double, channelCount: Int) -> [String: Any] {
            [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: channelCount,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
        }

        func writerOutputSettings(sampleRate: Double, channelCount: Int) -> [String: Any] {
            switch self {
            case .mediumQualityM4A:
                [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: channelCount,
                    AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
                    AVEncoderBitRateKey: bitRate(for: channelCount),
                ]
            case .compressedQualityWAV:
                readerOutputSettings(sampleRate: sampleRate, channelCount: channelCount)
            }
        }

        /// Fixed by the profile; the source rate never affects it.
        var targetSampleRate: Double {
            switch self {
            case .mediumQualityM4A:
                16000.0
            case .compressedQualityWAV:
                8000.0
            }
        }

        func targetChannelCount(from detected: Int) -> Int {
            switch self {
            case .mediumQualityM4A:
                let source = detected > 0 ? detected : 1
                return max(1, min(source, 2))
            case .compressedQualityWAV:
                return 1
            }
        }

        private func bitRate(for channelCount: Int) -> Int {
            let channels = max(channelCount, 1)
            return max(64000 * channels, 64000)
        }
    }

    private final class UncheckedSendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) {
            self.value = value
        }
    }

    struct Result {
        let data: Data
        let duration: TimeInterval
        let format: String
    }

    static func transcode(
        data: Data,
        fileExtension: String?,
        output: OutputFormat = .mediumQualityM4A,
    ) async throws -> Result {
        try await withWorkingDirectory { directory in
            let sanitizedExtension = sanitizedInputExtension(fileExtension)
            let inputURL = makeInputURL(in: directory, fileExtension: sanitizedExtension)
            try data.write(to: inputURL, options: .atomic)

            let sourceURL = try await resolveSourceURL(
                for: data,
                originalURL: inputURL,
                providedExtension: sanitizedExtension,
                workingDirectory: directory,
            )

            return try await transcode(sourceURL: sourceURL, output: output, workingDirectory: directory)
        }
    }

    static func transcode(url: URL, output: OutputFormat = .mediumQualityM4A) async throws -> Result {
        let data = try Data(contentsOf: url)
        let ext = url.pathExtension.isEmpty ? nil : url.pathExtension
        return try await transcode(data: data, fileExtension: ext, output: output)
    }

    private static func transcode(
        sourceURL: URL,
        output: OutputFormat,
        workingDirectory: URL,
    ) async throws -> Result {
        let asset = AVURLAsset(url: sourceURL)
        guard try await asset.load(.isExportable) else {
            throw AudioTranscoderError.assetNotSupported
        }
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard let track = tracks.first else {
            throw AudioTranscoderError.assetNotSupported
        }
        let formatDescriptions = try await track.load(.formatDescriptions)
        let detectedChannelCount = detectedChannelCount(from: formatDescriptions)
        let sampleRate = output.targetSampleRate
        let channelCount = output.targetChannelCount(from: detectedChannelCount)

        if let exported = try await exportUsingAssetExportSession(
            asset: asset,
            output: output,
            workingDirectory: workingDirectory,
        ) {
            return exported
        }

        return try await exportUsingReaderWriter(
            asset: asset,
            track: track,
            sampleRate: sampleRate,
            channelCount: channelCount,
            output: output,
            workingDirectory: workingDirectory,
        )
    }

    private static func exportUsingAssetExportSession(
        asset: AVAsset,
        output: OutputFormat,
        workingDirectory: URL,
    ) async throws -> Result? {
        guard output != .compressedQualityWAV else {
            return nil
        }

        var visitedPresets: Set<String> = []
        let presets = output.preferredExportPresets + AVAssetExportSession.allExportPresets()

        for preset in presets where visitedPresets.insert(preset).inserted {
            guard let session = AVAssetExportSession(asset: asset, presetName: preset) else { continue }
            guard session.supportedFileTypes.contains(output.fileType) else { continue }

            let outputURL = workingDirectory
                .appendingPathComponent("export")
                .appendingPathExtension(output.fileExtension)
            if FileManager.default.fileExists(atPath: outputURL.path) {
                try? FileManager.default.removeItem(at: outputURL)
            }

            session.outputFileType = output.fileType
            session.outputURL = outputURL
            session.shouldOptimizeForNetworkUse = output.optimizeForNetworkUse
            session.audioTimePitchAlgorithm = .timeDomain

            do {
                try await export(using: session)
            } catch AudioTranscoderError.exportFailed {
                continue
            }

            let duration = try await loadDurationSeconds(of: asset)
            let data = try await readExportedData(from: outputURL)
            try? FileManager.default.removeItem(at: outputURL)

            return Result(data: data, duration: duration, format: output.fileExtension)
        }

        return nil
    }

    private static func exportUsingReaderWriter(
        asset: AVAsset,
        track: AVAssetTrack,
        sampleRate: Double,
        channelCount: Int,
        output: OutputFormat,
        workingDirectory: URL,
    ) async throws -> Result {
        let reader = try AVAssetReader(asset: asset)
        let readerOutput = AVAssetReaderTrackOutput(
            track: track,
            outputSettings: output.readerOutputSettings(sampleRate: sampleRate, channelCount: channelCount),
        )
        readerOutput.alwaysCopiesSampleData = false
        guard reader.canAdd(readerOutput) else {
            throw AudioTranscoderError.readerWriterFailed("Unable to add reader output")
        }
        reader.add(readerOutput)

        let outputURL = workingDirectory
            .appendingPathComponent("writer")
            .appendingPathExtension(output.fileExtension)
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: output.fileType)
        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: output.writerOutputSettings(sampleRate: sampleRate, channelCount: channelCount),
        )
        writerInput.expectsMediaDataInRealTime = false
        guard writer.canAdd(writerInput) else {
            throw AudioTranscoderError.readerWriterFailed("Unable to add writer input")
        }
        writer.add(writerInput)

        let readerBox = UncheckedSendableBox(reader)
        let readerOutputBox = UncheckedSendableBox(readerOutput)
        let writerBox = UncheckedSendableBox(writer)
        let writerInputBox = UncheckedSendableBox(writerInput)
        let outputURLBox = UncheckedSendableBox(outputURL)
        let duration = try await loadDurationSeconds(of: asset)

        return try await withCheckedThrowingContinuation { continuation in
            let queue = DispatchQueue(label: "AudioTranscoder.Writer")

            func finish(with error: Error?) {
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    do {
                        let data = try Data(contentsOf: outputURLBox.value)
                        try? FileManager.default.removeItem(at: outputURLBox.value)
                        continuation.resume(returning: Result(
                            data: data,
                            duration: duration,
                            format: output.fileExtension,
                        ))
                    } catch {
                        continuation.resume(throwing: AudioTranscoderError.readerWriterFailed(error.localizedDescription))
                    }
                }
            }

            guard writerBox.value.startWriting() else {
                finish(with: writerBox.value.error ?? AudioTranscoderError.readerWriterFailed("Failed to start writer"))
                return
            }
            guard readerBox.value.startReading() else {
                finish(with: readerBox.value.error ?? AudioTranscoderError.readerWriterFailed("Failed to start reader"))
                return
            }

            writerBox.value.startSession(atSourceTime: .zero)

            writerInputBox.value.requestMediaDataWhenReady(on: queue) {
                while writerInputBox.value.isReadyForMoreMediaData {
                    if let buffer = readerOutputBox.value.copyNextSampleBuffer() {
                        if !writerInputBox.value.append(buffer) {
                            finish(with: writerBox.value.error ?? AudioTranscoderError.readerWriterFailed("Failed to append audio sample"))
                            return
                        }
                    } else {
                        writerInputBox.value.markAsFinished()
                        writerBox.value.finishWriting {
                            if writerBox.value.status == .completed {
                                finish(with: nil)
                            } else {
                                finish(with: writerBox.value.error ?? AudioTranscoderError.readerWriterFailed("Writer failed"))
                            }
                        }
                        break
                    }
                }
            }
        }
    }

    private static func withWorkingDirectory<R>(_ operation: (URL) async throws -> R) async throws -> R {
        let root = disposableResourcesDir.appendingPathComponent("AudioTranscoder", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        do {
            let result = try await operation(directory)
            try? FileManager.default.removeItem(at: directory)
            return result
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func makeInputURL(in directory: URL, fileExtension: String?) -> URL {
        var url = directory.appendingPathComponent("input")
        if let fileExtension, !fileExtension.isEmpty {
            url.appendPathExtension(fileExtension)
        }
        return url
    }

    private static func sanitizedInputExtension(_ fileExtension: String?) -> String? {
        guard let fileExtension else { return nil }
        let trimmed = fileExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed.lowercased()
    }

    private static func resolveSourceURL(
        for data: Data,
        originalURL: URL,
        providedExtension: String?,
        workingDirectory: URL,
    ) async throws -> URL {
        if await canDecodeAudio(at: originalURL) {
            return originalURL
        }

        for ext in candidateExtensions(including: providedExtension) {
            let candidateURL = workingDirectory
                .appendingPathComponent("input")
                .appendingPathExtension(ext)

            if candidateURL == originalURL {
                continue
            }

            if FileManager.default.fileExists(atPath: candidateURL.path) {
                try? FileManager.default.removeItem(at: candidateURL)
            }

            do {
                try data.write(to: candidateURL, options: .atomic)
            } catch {
                continue
            }

            if await canDecodeAudio(at: candidateURL) {
                return candidateURL
            }
        }

        throw AudioTranscoderError.assetNotSupported
    }

    private static func candidateExtensions(including provided: String?) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []

        func register(_ ext: String) {
            let normalized = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !seen.contains(normalized) else { return }
            seen.insert(normalized)
            ordered.append(normalized)
        }

        if let provided {
            register(provided)
            if let type = UTType(filenameExtension: provided) {
                for ext in type.tags[.filenameExtension] ?? [] {
                    register(ext)
                }
            }
        }

        for ext in ["m4a", "aac", "mp3", "wav", "flac", "aiff", "aif", "caf", "ogg", "opus", "amr", "wma"] {
            register(ext)
        }

        return ordered
    }

    private static func canDecodeAudio(at url: URL) async -> Bool {
        let asset = AVURLAsset(url: url)
        do {
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            return !tracks.isEmpty
        } catch {
            return false
        }
    }

    private static func loadDurationSeconds(of asset: AVAsset) async throws -> TimeInterval {
        let duration = try await asset.load(.duration)
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : 0
    }

    private static func readExportedData(
        from url: URL,
        retries: Int = 20,
        delay: Duration = .milliseconds(50),
    ) async throws -> Data {
        var lastError: Error?

        for attempt in 0 ..< retries {
            do {
                return try Data(contentsOf: url)
            } catch {
                lastError = error
                if attempt + 1 < retries {
                    try await Task.sleep(for: delay)
                }
            }
        }

        throw lastError ?? AudioTranscoderError.exportFailed("Exported file was not created.")
    }

    private static func detectedChannelCount(from descriptions: [CMFormatDescription]) -> Int {
        descriptions.compactMap { description -> Int? in
            guard CMFormatDescriptionGetMediaType(description) == kCMMediaType_Audio,
                  let stream = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee
            else {
                return nil
            }
            let channels = Int(stream.mChannelsPerFrame)
            return channels > 0 ? channels : nil
        }.first ?? 0
    }

    private static func export(using session: AVAssetExportSession) async throws {
        let sessionBox = UncheckedSendableBox(session)
        try await withCheckedThrowingContinuation { continuation in
            sessionBox.value.exportAsynchronously {
                switch sessionBox.value.status {
                case .completed:
                    continuation.resume(returning: ())
                case .failed:
                    let message = sessionBox.value.error?.localizedDescription ?? "Unknown Error"
                    continuation.resume(throwing: AudioTranscoderError.exportFailed(message))
                case .cancelled:
                    continuation.resume(throwing: AudioTranscoderError.exportFailed("Cancelled"))
                default:
                    let message = sessionBox.value.error?.localizedDescription ?? "Unknown Error"
                    continuation.resume(throwing: AudioTranscoderError.exportFailed(message))
                }
            }
        }
    }
}

extension AudioTranscoderError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .assetNotSupported:
            String(localized: "This audio asset is not supported.")
        case let .exportFailed(message):
            message
        case let .readerWriterFailed(message):
            message
        }
    }
}

//
//  PrivateCloudComputeRequestLog.swift
//  FlowDown
//
//  Writes every stage of a Private Cloud Compute request to the in-app log
//  (Settings → Logs, category Model, prefix [PCC]): the state before the
//  request (entitlement, availability, quota), what the framework streamed,
//  how the request ended, and every error in full. A cloud reply that never
//  arrives must leave a trace there.
//

import ChatClientKit
import Foundation
import FoundationModels

final class PrivateCloudComputeRequestLog: Sendable {
    /// How often a request that has produced nothing yet is noted as waiting.
    static let waitingInterval: Duration = .seconds(15)
    /// Every snapshot is counted, but only the first and every this many
    /// after it are written, so a long reply doesn't flood the log.
    static let snapshotLogStride = 100

    enum Level: Sendable {
        case info
        case error
    }

    let id: String
    private let write: @Sendable (Level, String) -> Void

    /// - Parameter write: Where lines go; the in-app log unless a test
    ///   collects them.
    init(
        id: String = String(UUID().uuidString.prefix(8)),
        write: @escaping @Sendable (Level, String) -> Void = { PrivateCloudComputeRequestLog.writeToAppLog($0, $1) },
    ) {
        self.id = id
        self.write = write
    }

    // MARK: Writing

    /// The resolver files any `fileID` containing "model" under Model.
    private static let logFileID = "PrivateCloudComputeModel"

    static func writeToAppLog(_ level: Level, _ message: String) {
        switch level {
        case .info: Logger.model.infoFile(message, fileID: logFileID)
        case .error: Logger.model.errorFile(message, fileID: logFileID)
        }
    }

    func info(_ message: String) {
        write(.info, "[PCC \(id)] \(message)")
    }

    func error(_ message: String) {
        write(.error, "[PCC \(id)] \(message)")
    }

    // MARK: State

    /// Entitlement, availability, quota and platform, read just before a request.
    static func stateDescription() -> String {
        var parts: [String] = []
        parts.append("entitlement=\(PrivateCloudComputeEntitlement.diagnosticDescription)")
        parts.append("availability=\(PrivateCloudComputeCenter.shared.availabilityState)")
        #if compiler(>=6.4)
            if #available(iOS 27.0, macCatalyst 27.0, *) {
                let model = PrivateCloudComputeModel.shared.languageModel
                parts.append("frameworkAvailability=\(model.availability)")
                parts.append("quota=\(quotaDescription(model.quotaUsage))")
            }
        #endif
        if #available(iOS 26.0, macCatalyst 26.0, *) {
            parts.append("onDeviceAvailability=\(SystemLanguageModel.default.availability)")
        }
        #if DEBUG
            if let fixture = PrivateCloudComputeFixture.current {
                parts.append("fixture=\(fixture.rawValue)")
            }
            parts.append("build=debug")
        #else
            parts.append("build=release")
        #endif
        #if targetEnvironment(macCatalyst)
            parts.append("platform=macCatalyst")
        #else
            parts.append("platform=iOS")
        #endif
        parts.append("os=\(ProcessInfo.processInfo.operatingSystemVersionString)")
        parts.append("sdkCompiledIn=\(PrivateCloudComputeIdentity.isCompiledIn)")
        return parts.joined(separator: ", ")
    }

    #if compiler(>=6.4)
        @available(iOS 27.0, macCatalyst 27.0, *)
        static func quotaDescription(_ usage: PrivateCloudComputeLanguageModel.QuotaUsage) -> String {
            var status = usage.isLimitReached ? "limitReached" : "belowLimit"
            if case let .belowLimit(info) = usage.status, info.isApproachingLimit {
                status += "(approaching)"
            }
            let reset = usage.resetDate.map { ISO8601DateFormatter().string(from: $0) } ?? "nil"
            let suggestion = usage.limitIncreaseSuggestion == nil ? "no" : "yes"
            return "\(status) isLimitReached=\(usage.isLimitReached) resetDate=\(reset) limitIncreaseSuggestion=\(suggestion)"
        }
    #endif

    // MARK: Errors

    /// Everything an error says about itself on one line: its type, its
    /// debug text, the NSError domain and code, nested underlying errors, and
    /// how the app maps it.
    static func describe(_ error: any Error) -> String {
        var parts = ["\(type(of: error))", String(reflecting: error).replacingOccurrences(of: "\n", with: " ")]
        appendNSErrorDetail(error as NSError, to: &parts, depth: 0)
        if let failure = PrivateCloudComputeCenter.shared.failure(from: error) {
            parts.append("mapped=\(failure)")
        }
        return parts.joined(separator: " | ")
    }

    private static func appendNSErrorDetail(_ error: NSError, to parts: inout [String], depth: Int) {
        let indent = String(repeating: ">", count: depth)
        parts.append("\(indent)domain=\(error.domain) code=\(error.code) description=\(error.localizedDescription)")
        guard depth < 4 else { return }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError {
            appendNSErrorDetail(underlying, to: &parts, depth: depth + 1)
        }
        if let multiple = error.userInfo[NSMultipleUnderlyingErrorsKey] as? [NSError] {
            for underlying in multiple {
                appendNSErrorDetail(underlying, to: &parts, depth: depth + 1)
            }
        }
    }

    // MARK: Chat client events

    /// Writes what `PrivateCloudComputeChatClient` reports from inside the
    /// framework stream.
    func record(_ event: PrivateCloudComputeStreamEvent) {
        switch event {
        case let .sessionCreated(historyEntries, tools, instructionsLength, promptLength, reasoningDepth):
            info("session created: history=\(historyEntries) tools=\(tools) instructionsChars=\(instructionsLength) promptChars=\(promptLength) reasoning=\(reasoningDepth?.rawValue ?? "default")")
        case .requestSent:
            info("streamResponse called, waiting for the first snapshot")
        case let .snapshot(index, contentLength, reasoningLength, transcriptEntries):
            guard index == 1 || index % Self.snapshotLogStride == 0 else { return }
            info("snapshot #\(index): contentChars=\(contentLength) reasoningChars=\(reasoningLength) transcriptEntries=\(transcriptEntries)")
        case let .snapshotRewritten(field, previousLength, newLength):
            error("snapshot rewrote earlier \(field.rawValue) (\(previousLength) → \(newLength) chars); the changed part was not forwarded")
        case let .toolCallCaptured(name):
            info("tool call captured: \(name)")
        case let .finished(snapshots, contentLength, reasoningLength):
            info("framework stream finished: snapshots=\(snapshots) contentChars=\(contentLength) reasoningChars=\(reasoningLength)")
        case let .cancelled(snapshots):
            info("framework stream cancelled after \(snapshots) snapshots")
        case let .failed(snapshots, failure):
            error("framework stream threw after \(snapshots) snapshots: \(Self.describe(failure))")
        }
    }
}

/// Logs a Private Cloud Compute request from start to end around the chat
/// client that serves it: the start with the model's state, how long the
/// first chunk took, a note every `waitingInterval` while nothing has come,
/// chunk counts at the end, and every error. Chunks and errors pass through
/// unchanged.
final class PrivateCloudComputeLoggingChatService: ChatService {
    let inner: any ChatService
    let log: PrivateCloudComputeRequestLog

    var errorCollector: ErrorCollector {
        inner.errorCollector
    }

    init(inner: any ChatService, log: PrivateCloudComputeRequestLog) {
        self.inner = inner
        self.log = log
    }

    struct Counts {
        var reasoningChunks = 0
        var reasoningChars = 0
        var textChunks = 0
        var textChars = 0
        var toolCalls = 0
        var images = 0

        var isEmpty: Bool {
            reasoningChunks == 0 && textChunks == 0 && toolCalls == 0 && images == 0
        }

        mutating func add(_ chunk: ChatResponseChunk) {
            switch chunk {
            case let .reasoning(value):
                reasoningChunks += 1
                reasoningChars += value.count
            case let .text(value):
                textChunks += 1
                textChars += value.count
            case .tool:
                toolCalls += 1
            case .image:
                images += 1
            }
        }

        var summary: String {
            "reasoningChunks=\(reasoningChunks) (\(reasoningChars) chars) textChunks=\(textChunks) (\(textChars) chars) toolCalls=\(toolCalls) images=\(images)"
        }
    }

    static func kind(of chunk: ChatResponseChunk) -> String {
        switch chunk {
        case .reasoning: "reasoning"
        case .text: "text"
        case .tool: "tool"
        case .image: "image"
        }
    }

    func streamingChat(body: ChatRequestBody) async throws -> AnyAsyncSequence<ChatResponseChunk> {
        let log = log
        let started = ContinuousClock.now
        log.info("request start: model=\(PrivateCloudComputeCenter.modelIdentifier) messages=\(body.messages.count) tools=\(body.tools?.count ?? 0) maxCompletionTokens=\(body.maxCompletionTokens.map(String.init) ?? "nil"); \(PrivateCloudComputeRequestLog.stateDescription())")

        let sequence: AnyAsyncSequence<ChatResponseChunk>
        do {
            sequence = try await inner.streamingChat(body: body)
        } catch {
            log.error("request failed before streaming: \(PrivateCloudComputeRequestLog.describe(error))")
            throw error
        }

        return AnyAsyncSequence(AsyncThrowingStream { continuation in
            let task = Task {
                var counts = Counts()
                let waiting = Task {
                    var waited: Duration = .zero
                    while !Task.isCancelled {
                        try? await Task.sleep(for: PrivateCloudComputeRequestLog.waitingInterval)
                        guard !Task.isCancelled else { return }
                        waited += PrivateCloudComputeRequestLog.waitingInterval
                        log.info("still waiting for the first chunk after \(waited.components.seconds)s")
                    }
                }
                defer { waiting.cancel() }

                do {
                    for try await chunk in sequence {
                        if counts.isEmpty {
                            waiting.cancel()
                            log.info("first chunk (\(Self.kind(of: chunk))) after \(ContinuousClock.now - started)")
                        }
                        counts.add(chunk)
                        continuation.yield(chunk)
                    }
                    let elapsed = ContinuousClock.now - started
                    if counts.isEmpty {
                        log.error("request finished without any output after \(elapsed)")
                    } else {
                        log.info("request finished after \(elapsed): \(counts.summary)")
                    }
                    continuation.finish()
                } catch {
                    let elapsed = ContinuousClock.now - started
                    if error is CancellationError || Task.isCancelled {
                        log.info("request cancelled after \(elapsed): \(counts.summary)")
                    } else {
                        log.error("request failed after \(elapsed): \(PrivateCloudComputeRequestLog.describe(error)); \(counts.summary)")
                    }
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { reason in
                if case .cancelled = reason {
                    log.info("consumer stopped the request")
                }
                task.cancel()
            }
        })
    }
}

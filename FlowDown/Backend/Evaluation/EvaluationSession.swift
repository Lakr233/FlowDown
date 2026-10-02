//
//  EvaluationSession.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import Foundation
import OSLog

class EvaluationSession: Codable, @unchecked Sendable {
    let id: UUID
    let createdAt: Date
    let modelIdentifier: ModelManager.ModelIdentifier
    let manifests: [EvaluationManifest]
    let maxConcurrentRequests: Int
    let shots: Int

    init(options: EvaluationOptions) {
        id = .init()
        createdAt = .init()
        modelIdentifier = options.modelIdentifier
        manifests = EvaluationSession.detachedCopy(of: options.createFinalManifest())
        maxConcurrentRequests = options.options.maxConcurrentRequests
        shots = options.options.shots
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modelIdentifier, manifests, maxConcurrentRequests, shots
    }

    private var runningTask: Task<Void, Never>?

    /// Stands in for live inference on each attempt so tests can drive a run without a model.
    var singleShotOverride: ((EvaluationManifest.Suite.Case) async -> EvaluationManifest.Suite.Case.Result.Outcome)?

    private let persistenceQueue = DispatchQueue(label: "FlowDown.EvaluationSession.persistence")
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var lastSaveTime: Date = .distantPast
    private let saveDebounceInterval: TimeInterval = 0.75
}

private extension EvaluationSession {
    /// Cases are classes whose results change during a run, and the options keep
    /// handing out the same instances. Copying through Codable gives each session
    /// its own cases with the same ids and content, and without earlier results.
    /// The decoder skips the instruction that `Case.init` prepends to bundled cases.
    static func detachedCopy(of manifests: [EvaluationManifest]) -> [EvaluationManifest] {
        let copies: [EvaluationManifest]
        do {
            let data = try JSONEncoder().encode(manifests)
            copies = try JSONDecoder().decode([EvaluationManifest].self, from: data)
        } catch {
            assertionFailure("failed to copy evaluation manifests: \(error)")
            return manifests
        }
        for manifest in copies {
            for suite in manifest.suites {
                for caseItem in suite.cases {
                    caseItem.results = []
                }
            }
        }
        return copies
    }

    func scheduleSave() {
        persistenceQueue.async { [weak self] in
            guard let self else { return }

            let now = Date()
            if now.timeIntervalSince(lastSaveTime) >= saveDebounceInterval {
                lastSaveTime = now
                pendingSaveWorkItem?.cancel()
                pendingSaveWorkItem = nil
                _ = try? EvaluationSessionManager.shared.save(self)
                return
            }

            pendingSaveWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                lastSaveTime = Date()
                _ = try? EvaluationSessionManager.shared.save(self)
            }
            pendingSaveWorkItem = item
            persistenceQueue.asyncAfter(deadline: .now() + saveDebounceInterval, execute: item)
        }
    }

    func cancelPendingSave() {
        persistenceQueue.async { [weak self] in
            guard let self else { return }
            pendingSaveWorkItem?.cancel()
            pendingSaveWorkItem = nil
        }
    }
}

extension EvaluationSession {
    var isRunning: Bool {
        runningTask != nil
    }

    var allCases: [EvaluationManifest.Suite.Case] {
        var cases: [EvaluationManifest.Suite.Case] = []
        for manifest in manifests {
            for suite in manifest.suites {
                cases.append(contentsOf: suite.cases)
            }
        }
        return cases
    }

    var isCompleted: Bool {
        let cases = allCases
        guard !cases.isEmpty else { return true }
        return cases.allSatisfy { caseItem in
            let outcome = caseItem.results.last?.outcome ?? .notDetermined
            return outcome != .notDetermined && outcome != .processing
        }
    }

    func stopAndDispose(save: Bool = true) {
        runningTask?.cancel()
        runningTask = nil
        cancelPendingSave()
        if save {
            _ = try? EvaluationSessionManager.shared.save(self)
        }
    }
}

extension EvaluationSession {
    @objc func resume() {
        guard runningTask == nil else { return }
        runningTask = Task { [weak self] in
            guard let self else { return }
            await startEvaluation()
        }
    }

    private func startEvaluation() async {
        // A re-run requested while the group is busy marks its case `.notDetermined`
        // after `casesToRun` was collected, so collect again until none are left.
        repeat {
            // Prepare cases for execution
            // We only want to run cases that are NOT completed.
            var casesToRun: [EvaluationManifest.Suite.Case] = []
            for caseItem in allCases {
                let currentOutcome = caseItem.results.last?.outcome ?? .notDetermined
                switch currentOutcome {
                case .pass, .fail, .awaitingJudging:
                    // Already done, skip
                    continue
                case .processing, .notDetermined:
                    // Needs running. Reset processing to notDetermined for clean start
                    if caseItem.results.isEmpty {
                        caseItem.results.append(.init(outcome: .notDetermined))
                    } else {
                        caseItem.results[caseItem.results.count - 1].outcome = .notDetermined
                    }
                    casesToRun.append(caseItem)
                }
            }

            scheduleSave()

            // NOTE: `AsyncStream` is intended for a single consumer.
            // The previous implementation iterated the same stream from multiple tasks,
            // which can lead to duplicated work (same case evaluated multiple times).
            // Use a bounded task-group pattern to enforce `maxConcurrentRequests` safely.
            await withTaskGroup(of: Void.self) { group in
                var iterator = casesToRun.makeIterator()
                let workerCount = max(1, min(self.maxConcurrentRequests, casesToRun.count))

                for _ in 0 ..< workerCount {
                    guard let caseItem = iterator.next() else { break }
                    group.addTask {
                        if Task.isCancelled { return }
                        await self.evaluate(caseItem)
                    }
                }

                while let _ = await group.next() {
                    if Task.isCancelled { return }
                    guard let nextCase = iterator.next() else { continue }
                    group.addTask {
                        if Task.isCancelled { return }
                        await self.evaluate(nextCase)
                    }
                }
            }
        } while !Task.isCancelled && allCases.contains(where: { caseItem in
            (caseItem.results.last?.outcome ?? .notDetermined) == .notDetermined
        })

        let id = id
        if !Task.isCancelled {
            logger.info("Evaluation session \(id) completed")
        } else {
            logger.info("Evaluation session \(id) stopped")
        }

        cancelPendingSave()
        _ = try? EvaluationSessionManager.shared.save(self)

        await MainActor.run {
            self.runningTask = nil
            NotificationCenter.default.post(name: .evaluationSessionDidUpdate, object: self)
        }
    }

    private func evaluate(_ caseItem: EvaluationManifest.Suite.Case) async {
        await updateResult(for: caseItem, outcome: .processing)

        var attempts = 0
        var stop = false

        while attempts < shots, !stop, !Task.isCancelled {
            attempts += 1

            let outcome = await performSingleShot(caseItem)

            // A stopped run cuts the response short; leave the case for resume to pick up.
            if Task.isCancelled {
                await updateResult(for: caseItem, outcome: .notDetermined)
                return
            }

            switch outcome {
            case .pass, .awaitingJudging:
                stop = true
                await updateResult(for: caseItem, outcome: outcome)
            case .fail:
                if attempts >= shots {
                    await updateResult(for: caseItem, outcome: .fail)
                }
            default:
                break
            }

            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .evaluationSessionDidUpdate, object: self)
            }
        }
    }

    private func updateResult(
        for caseItem: EvaluationManifest.Suite.Case,
        outcome: EvaluationManifest.Suite.Case.Result.Outcome
    ) async {
        guard let result = caseItem.results.last else { return }
        result.outcome = outcome
        scheduleSave()
    }

    private func performSingleShot(
        _ caseItem: EvaluationManifest.Suite.Case
    ) async -> EvaluationManifest.Suite.Case.Result.Outcome {
        if let singleShotOverride {
            return await singleShotOverride(caseItem)
        }

        var messages: [ChatRequestBody.Message] = []
        var tools: [ChatRequestBody.Tool] = []

        for content in caseItem.content {
            switch content.type {
            case .instruct:
                if let text = content.textRepresentation {
                    messages.append(.system(content: .text(text)))
                }
            case .request:
                if let text = content.textRepresentation {
                    messages.append(.user(content: .text(text)))
                }
            case .toolDefinition:
                if let toolRep = content.toolRepresentation {
                    tools.append(convertToTool(toolRep))
                }
            case .reasoning:
                if let text = content.textRepresentation {
                    messages.append(.assistant(content: nil, toolCalls: nil, reasoning: text))
                }
            case .reply:
                if let text = content.textRepresentation {
                    messages.append(.assistant(content: .text(text), toolCalls: nil, reasoning: nil))
                }
            default:
                break
            }
        }

        do {
            let response = try await ModelManager.shared.infer(
                with: modelIdentifier,
                input: messages,
                tools: tools.isEmpty ? nil : tools,
            )

            // A cancelled stream ends without throwing, so the response may be cut off.
            if Task.isCancelled { return .notDetermined }

            // Save output to result
            if let result = caseItem.results.last {
                var output: [EvaluationManifest.Suite.Case.Content] = []
                if !response.reasoning.isEmpty {
                    output.append(.init(type: .reasoning, textRepresentation: response.reasoning))
                }
                if !response.text.isEmpty {
                    output.append(.init(type: .reply, textRepresentation: response.text))
                }
                for toolMsg in response.tools {
                    let toolRep: EvaluationManifest.Suite.Case.ToolRepresentation? = if
                        let data = toolMsg.args.data(using: .utf8),
                        let params = try? JSONDecoder().decode([String: AnyCodingValue].self, from: data)
                    {
                        .init(name: toolMsg.name, description: "", parameters: params)
                    } else {
                        .init(name: toolMsg.name, description: "", parameters: [:])
                    }
                    output.append(
                        .init(type: .toolRequest, textRepresentation: toolMsg.args, toolRepresentation: toolRep)
                    )
                }
                result.output = output
                scheduleSave()
            }

            return verify(response: response, verifiers: caseItem.verifier)
        } catch {
            return .fail
        }
    }

    private func convertToTool(_ rep: EvaluationManifest.Suite.Case.ToolRepresentation) -> ChatRequestBody.Tool {
        .function(
            name: rep.name,
            description: rep.description,
            parameters: rep.requestParameters,
            strict: false,
        )
    }

    func verify(
        response: ChatResponse,
        verifiers: [EvaluationManifest.Suite.Case.Verifier]
    ) -> EvaluationManifest.Suite.Case.Result.Outcome {
        // Check for manual verification requirement
        let requiresManualJudgment = verifiers.contains(where: { if case .open = $0 { return true }; return false })

        // Check automatic verifiers
        var automaticPass = true

        for verifier in verifiers {
            switch verifier {
            case .open:
                continue
            case let .match(pattern):
                if response.text.trimmingCharacters(in: .whitespacesAndNewlines) != pattern { automaticPass = false }
            case let .matchCaseInsensitive(pattern):
                if response.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != pattern.lowercased() {
                    automaticPass = false
                }
            case let .contains(pattern):
                if !response.text.contains(pattern) { automaticPass = false }
            case let .containsCaseInsensitive(pattern):
                if !response.text.lowercased().contains(pattern.lowercased()) { automaticPass = false }
            case let .toolCalled(name):
                if !response.tools.contains(where: { $0.name == name }) { automaticPass = false }
            case let .matchRegularExpression(pattern):
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let range = NSRange(location: 0, length: response.text.utf16.count)
                    if regex.firstMatch(in: response.text, options: [], range: range) == nil {
                        automaticPass = false
                    }
                } else {
                    automaticPass = false
                }
            case let .tool(parameter, value):
                let matching = response.tools.contains(where: { toolReq in
                    guard let argsData = toolReq.args.data(using: String.Encoding.utf8),
                          let args = try? JSONDecoder().decode([String: AnyCodingValue].self, from: argsData),
                          let paramValue = args[parameter]
                    else {
                        return false
                    }
                    return toolArgument(paramValue, matches: value)
                })
                if !matching { automaticPass = false }
            }

            if !automaticPass { break }
        }

        if !automaticPass { return .fail }
        if requiresManualJudgment { return .awaitingJudging }
        return .pass
    }

    /// Compares a tool-call argument with the expected value by JSON structure.
    /// An integer equals a double of the same value, and a string equals a scalar
    /// whose plain text it spells, since models often quote numbers and booleans.
    private func toolArgument(_ lhs: AnyCodingValue, matches rhs: AnyCodingValue) -> Bool {
        switch (lhs, rhs) {
        case let (.string(a), .string(b)):
            return a == b
        case let (.string(text), scalar), let (scalar, .string(text)):
            return toolArgumentText(scalar) == text
        case let (.int(a), .double(b)), let (.double(b), .int(a)):
            return Double(a) == b
        case let (.array(a), .array(b)):
            return a.count == b.count && zip(a, b).allSatisfy { toolArgument($0, matches: $1) }
        case let (.object(a), .object(b)):
            return a.count == b.count && a.allSatisfy { entry in
                guard let other = b[entry.key] else { return false }
                return toolArgument(entry.value, matches: other)
            }
        default:
            return lhs == rhs
        }
    }

    private func toolArgumentText(_ value: AnyCodingValue) -> String? {
        switch value {
        case .null:
            "null"
        case let .bool(bool):
            String(bool)
        case let .int(int):
            String(int)
        case let .double(double):
            Int(exactly: double).map { String($0) } ?? String(double)
        case .string, .array, .object:
            nil
        }
    }
}

extension Notification.Name {
    static let evaluationSessionDidUpdate = Notification.Name("evaluationSessionDidUpdate")
}

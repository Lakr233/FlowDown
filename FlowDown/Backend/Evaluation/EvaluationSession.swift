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
        manifests = options.createFinalManifest()
        maxConcurrentRequests = options.options.maxConcurrentRequests
        shots = options.options.shots
    }

    private enum CodingKeys: String, CodingKey {
        case id, createdAt, modelIdentifier, manifests, maxConcurrentRequests, shots
    }

    private var runningTask: Task<Void, Never>?

    private let persistenceQueue = DispatchQueue(label: "FlowDown.EvaluationSession.persistence")
    private var pendingSaveWorkItem: DispatchWorkItem?
    private var lastSaveTime: Date = .distantPast
    private let saveDebounceInterval: TimeInterval = 0.75
}

private extension EvaluationSession {
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

        while attempts < shots, !stop {
            attempts += 1

            let outcome = await performSingleShot(caseItem)

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

    private func updateResult(for caseItem: EvaluationManifest.Suite.Case, outcome: EvaluationManifest.Suite.Case.Result.Outcome) async {
        guard let result = caseItem.results.last else { return }
        result.outcome = outcome
        scheduleSave()
    }

    private func performSingleShot(_ caseItem: EvaluationManifest.Suite.Case) async -> EvaluationManifest.Suite.Case.Result.Outcome {
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
                    output.append(.init(type: .toolRequest, textRepresentation: toolMsg.args, toolRepresentation: toolRep))
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

    func verify(response: ChatResponse, verifiers: [EvaluationManifest.Suite.Case.Verifier]) -> EvaluationManifest.Suite.Case.Result.Outcome {
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
                if response.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() != pattern.lowercased() { automaticPass = false }
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
                let encoder = JSONEncoder()
                guard let valueData = try? encoder.encode(value),
                      let valueStr = String(data: valueData, encoding: .utf8)
                else {
                    automaticPass = false
                    continue
                }

                let matching = response.tools.contains(where: { toolReq in
                    guard let argsData = toolReq.args.data(using: String.Encoding.utf8),
                          let args = try? JSONSerialization.jsonObject(with: argsData) as? [String: Any]
                    else {
                        return false
                    }
                    if let paramValue = args[parameter] {
                        return String(describing: paramValue) == valueStr.replacingOccurrences(of: "\"", with: "")
                    }
                    return false
                })
                if !matching { automaticPass = false }
            }

            if !automaticPass { break }
        }

        if !automaticPass { return .fail }
        if requiresManualJudgment { return .awaitingJudging }
        return .pass
    }
}

extension Notification.Name {
    static let evaluationSessionDidUpdate = Notification.Name("evaluationSessionDidUpdate")
}

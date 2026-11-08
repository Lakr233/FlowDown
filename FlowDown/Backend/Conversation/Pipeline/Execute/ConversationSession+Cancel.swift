//
//  ConversationSession+Cancel.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/3/25.
//

import Combine
import Foundation
import Storage

struct InferenceUserCancellationError: LocalizedError {
    var errorDescription: String? {
        String(localized: "User cancelled the operation.")
    }
}

extension ConversationSession {
    func cancelCurrentTask(completion: @escaping () -> Void) {
        guard let task = currentTask else {
            Task { @MainActor in
                completion()
            }
            return
        }
        Logger.app.infoFile("cancel current task for conversation: \(id)")
        task.cancel()
        // wait until self.currentTask is nil
        Task.detached { [self] in
            while currentTask != nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            Logger.app.infoFile("current task cancelled for conversation: \(id)")
            await MainActor.run {
                ConversationSessionManager.shared.markSessionCompleted(self.id)
                completion()
            }
        }
    }

    func checkCancellation() throws {
        guard let task = currentTask, !task.isCancelled else {
            throw InferenceUserCancellationError()
        }
    }
}

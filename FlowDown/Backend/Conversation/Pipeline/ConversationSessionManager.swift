//
//  ConversationSessionManager.swift
//  FlowDown
//
//  Created by ktiays on 2025/2/12.
//

import ChatClientKit
import Combine
import ConfigurableKit
import Foundation
import Storage

final class ConversationSessionManager {
    typealias Session = ConversationSession

    // MARK: - Singleton

    static let shared = ConversationSessionManager()

    // MARK: - State

    private var sessions: [Conversation.ID: Session] = [:]
    private var messageChangedObserver: Any?
    private var pendingRefresh: Set<Conversation.ID> = []
    private let logger = Logger(subsystem: "wiki.qaq.flowdown", category: "ConversationSessionManager")

    private var executingSessions: Set<Conversation.ID> = []
    let executingSessionsPublisher = CurrentValueSubject<Set<Conversation.ID>, Never>([])

    @Published private(set) var streamingSessionTextCount: Int = 0
    private var cancellables: Set<AnyCancellable> = []

    // MARK: - Lifecycle

    private init() {
        messageChangedObserver = NotificationCenter.default.addObserver(
            forName: SyncEngine.MessageChanged,
            object: nil,
            queue: .main,
        ) { [weak self] notification in
            guard let self else { return }
            handleMessageChanged(notification)
        }

        ConfigurableKit.publisher(forKey: LiveActivitySetting.storageKey, type: Bool.self)
            .ensureMainThread()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshLiveActivity()
                }
            }
            .store(in: &cancellables)

        ConfigurableKit.publisher(forKey: StreamAudioEffectSetting.storageKey, type: Int.self)
            .ensureMainThread()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshLiveActivity()
                }
            }
            .store(in: &cancellables)
    }

    deinit {
        if let messageChangedObserver {
            NotificationCenter.default.removeObserver(messageChangedObserver)
        }
    }

    // MARK: - Public APIs

    func session(for conversationID: Conversation.ID) -> Session {
        if let cached = sessions[conversationID] { return cached }
        #if DEBUG
            ConversationSession.allowedInit = conversationID
        #endif
        let newSession = Session(id: conversationID)
        sessions[conversationID] = newSession
        return newSession
    }

    func invalidateSession(for conversationID: Conversation.ID) {
        sessions.removeValue(forKey: conversationID)
        pendingRefresh.remove(conversationID)
        markSessionCompleted(conversationID)
    }

    // MARK: - Message Change Handling

    private func handleMessageChanged(_ notification: Notification) {
        // Only update message lists; do not touch conversation sidebar (no scanAll here).
        guard let info = notification.userInfo?[SyncEngine.MessageNotificationKey] as? MessageNotificationInfo else {
            logger.infoFile("MessageChanged without detail; refreshing all cached sessions")
            for (_, session) in sessions {
                refreshSafely(session)
            }
            return
        }

        for cid in Set(info.modifications.keys).union(info.deletions.keys) {
            guard let session = sessions[cid] else { continue }
            refreshSafely(session)
        }
    }

    private func refreshSafely(_ session: Session) {
        // Avoid refreshing while a streaming task is active to prevent UI errors.
        if let task = session.currentTask, !task.isCancelled {
            logger.debugFile("Defer refresh for session \(String(describing: session.id)) due to active task")
            pendingRefresh.insert(session.id)
            return
        }
        // No active task or task is cancelled, safe to refresh immediately
        session.refreshContentsFromDatabase()
    }

    func resolvePendingRefresh(for sessionID: Conversation.ID) {
        guard pendingRefresh.contains(sessionID) else { return }
        guard let session = sessions[sessionID] else {
            pendingRefresh.remove(sessionID)
            return
        }
        // Task completed, now safe to refresh
        logger.infoFile("Executing pending refresh for session \(String(describing: sessionID))")
        session.refreshContentsFromDatabase()
        pendingRefresh.remove(sessionID)
    }

    // MARK: - Execution State Management

    func markSessionExecuting(_ sessionID: Conversation.ID) {
        executingSessions.insert(sessionID)
        executingSessionsPublisher.send(executingSessions)

        Task { @MainActor in
            refreshLiveActivity()
        }
    }

    func markSessionCompleted(_ sessionID: Conversation.ID) {
        executingSessions.remove(sessionID)
        executingSessionsPublisher.send(executingSessions)

        Task { @MainActor in
            if executingSessions.isEmpty {
                streamingSessionTextCount = 0
            }
            refreshLiveActivity()
        }
    }

    func isSessionExecuting(_ sessionID: Conversation.ID) -> Bool {
        executingSessions.contains(sessionID)
    }

    var hasExecutingSessions: Bool {
        !executingSessions.isEmpty
    }

    /// Called when any streaming output receives new text.
    ///
    /// The caller should compare old/new output lengths and pass the delta here.
    /// This delta will be accumulated and forwarded to Live Activity updates.
    @MainActor
    func countIncomingTokens(_ count: Int) {
        guard count > 0 else { return }
        streamingSessionTextCount += count
        refreshLiveActivity()
    }

    @MainActor
    func refreshLiveActivity() {
        let audioEnabled = StreamAudioEffectSetting.configuredMode() != .off
        let enabled = LiveActivitySetting.isEnabled() && audioEnabled

        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 16.2, *) {
                LiveActivityService.shared.update(
                    conversationCount: executingSessions.count,
                    streamingSessionTextCount: streamingSessionTextCount,
                    enabled: enabled,
                )
            }
        #endif
    }
}

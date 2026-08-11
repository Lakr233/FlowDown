//
//  LiveActivityService.swift
//  FlowDown
//
//  Created by AI on 1/6/26.
//

import Foundation

#if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
    import ActivityKit

    @available(iOS 16.2, *)
    protocol LiveActivityControlling: AnyObject {
        func update(state: FlowDownWidgetsAttributes.ContentState) async
        func endImmediately() async
    }

    @available(iOS 16.2, *)
    final class ActivityKitLiveActivityController: LiveActivityControlling {
        private let activity: Activity<FlowDownWidgetsAttributes>

        init(activity: Activity<FlowDownWidgetsAttributes>) {
            self.activity = activity
        }

        func update(state: FlowDownWidgetsAttributes.ContentState) async {
            await activity.update(
                ActivityContent(state: state, staleDate: nil),
            )
        }

        func endImmediately() async {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }

    @MainActor
    @available(iOS 16.2, *)
    final class LiveActivityService {
        typealias ExistingActivityProvider = () -> (any LiveActivityControlling)?
        typealias ActivityControllerFactory = (
            _ attributes: FlowDownWidgetsAttributes,
            _ state: FlowDownWidgetsAttributes.ContentState,
        ) throws -> any LiveActivityControlling
        typealias ExecutingSessionCountProvider = () -> Int

        static let shared = LiveActivityService()

        private var currentActivity: (any LiveActivityControlling)?
        private var autoDismissWhenCompleted: Bool = true
        private let existingActivityProvider: ExistingActivityProvider
        private let activityControllerFactory: ActivityControllerFactory
        private let executingSessionCountProvider: ExecutingSessionCountProvider

        init(
            existingActivityProvider: @escaping ExistingActivityProvider = {
                Activity<FlowDownWidgetsAttributes>.activities.first.map(ActivityKitLiveActivityController.init)
            },
            activityControllerFactory: @escaping ActivityControllerFactory = { attributes, state in
                let activity = try Activity.request(
                    attributes: attributes,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil,
                )
                return ActivityKitLiveActivityController(activity: activity)
            },
            executingSessionCountProvider: @escaping ExecutingSessionCountProvider = {
                ConversationSessionManager.shared.executingSessionsPublisher.value.count
            },
        ) {
            self.existingActivityProvider = existingActivityProvider
            self.activityControllerFactory = activityControllerFactory
            self.executingSessionCountProvider = executingSessionCountProvider
            currentActivity = existingActivityProvider()
        }

        func appWillEnterBackground() {
            autoDismissWhenCompleted = false
        }

        func appDidEnterForeground() {
            autoDismissWhenCompleted = true
            if executingSessionCountProvider() <= 0 {
                endIfNeeded()
            }
        }

        func update(conversationCount: Int, streamingSessionTextCount: Int, enabled: Bool) {
            guard enabled else {
                endIfNeeded()
                return
            }

            if autoDismissWhenCompleted, conversationCount <= 0 {
                endIfNeeded()
                return
            }

            let state = FlowDownWidgetsAttributes.ContentState(
                conversationCount: conversationCount,
                streamingSessionTextCount: streamingSessionTextCount,
            )

            if let activity = currentActivity {
                Task {
                    await activity.update(state: state)
                }
            } else {
                do {
                    let attributes = FlowDownWidgetsAttributes()
                    currentActivity = try activityControllerFactory(attributes, state)
                } catch {
                    logger.error("unable to start live activity \(error.localizedDescription)")
                }
            }
        }

        func endIfNeeded() {
            guard let activity = currentActivity else { return }
            currentActivity = nil
            Task {
                await activity.endImmediately()
            }
        }
    }

#endif

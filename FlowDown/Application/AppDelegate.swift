//
//  AppDelegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import AlertController
import ChatClientKit
import CloudKit
import Combine
import ConfigurableKit
import MarkdownView
import MLX
import ScrubberKit
import Storage
import UIKit

@objc(AppDelegate)
class AppDelegate: UIResponder, UIApplicationDelegate {
    private var templateMenuCancellable: AnyCancellable?
    private var isPresentingExitConfirmation = false

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions _: [UIApplication.LaunchOptionsKey: Any]? = nil,
    ) -> Bool {
        guard !RecoveryMode.isActivated else { return true }

        UITableView.appearance().backgroundColor = .clear
        UIButton.appearance().tintColor = .accent
        UITextView.appearance().tintColor = .accent
        UINavigationBar.appearance().tintColor = .accent
        UISwitch.appearance().onTintColor = .accent
        UIUserInterfaceStyle.subscribeToConfigurableItem()

        StreamAudioEffectSetting.subscribeToConfigurableItem()
        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
            LiveActivitySetting.subscribeToConfigurableItem()
        #endif
        _ = SoundEffectPlayer.shared

        MLX.GPU.subscribeToConfigurableItem()
        EditorBehavior.subscribeToConfigurableItem()
        MarkdownTheme.subscribeToConfigurableItem()
        ScrubberConfiguration.subscribeToConfigurableItem()
        ScrubberConfiguration.setup() // build access control rule

        AlertControllerConfiguration.alertImage = .avatar
        AlertControllerConfiguration.accentColor = .accent
        AlertControllerConfiguration.backgroundColor = .background
        AlertControllerConfiguration.separatorColor = SeparatorView.color

        DefaultMessageSanitizerConfiguration.placeholderText = String(
            localized: "Continue if not finished",
        )

        templateMenuCancellable = ChatTemplateManager.shared.$templates
            .sink { _ in
                Task { @MainActor in
                    UIMenuSystem.main.setNeedsRebuild()
                }
            }

        application.registerForRemoteNotifications()

        if SyncEngine.isSyncEnabled {
            Task {
                try? await syncEngine.fetchChanges()
            }
        }

        sdb.clearDeletedRecords()

        if let firstSeenTicketURL = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("first_seen_ticket.txt")
        {
            let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
            if !FileManager.default.fileExists(atPath: firstSeenTicketURL.path) {
                do {
                    try version.write(to: firstSeenTicketURL, atomically: true, encoding: .utf8)
                    logger.infoFile("wrote first seen ticket: \(version)")
                } catch {
                    logger.errorFile("failed to write first seen ticket: \(error)")
                }
            }
        }

        return true
    }

    func application(_: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken _: Data) {
        guard !RecoveryMode.isActivated else { return }
        logger.infoFile("Did register for remote notifications")
    }

    func application(_: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        guard !RecoveryMode.isActivated else { return }
        logger.errorFile("ERROR: Failed to register for notifications: \(error.localizedDescription)")
    }

    func application(_: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        guard let notification = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            completionHandler(.noData)
            return
        }
        logger.infoFile("Received cloudkit notification: \(notification)")

        guard notification.containerIdentifier == CloudKitConfig.containerIdentifier else {
            completionHandler(.noData)
            return
        }

        Task {
            do {
                logger.infoFile("cloudkit notification fetchChanges")
                try await syncEngine.fetchChanges()
                completionHandler(.newData)
            } catch {
                logger.errorFile("cloudkit notification fetchLatestChanges: \(error)")
                completionHandler(.failed)
            }
        }
    }

    #if targetEnvironment(macCatalyst)
        @objc func terminate(_: Any?) {
            requestApplicationExit()
        }

        @objc override func performClose(_: Any?) {
            requestApplicationExit()
        }

        func requestApplicationExit() {
            requestProtectedTermination {
                terminateApplication()
            }
        }

        private var hasExecutingConversations: Bool {
            ConversationSessionManager.shared.hasExecutingSessions
        }

        private func requestProtectedTermination(_ action: @escaping () -> Void) {
            guard hasExecutingConversations else {
                action()
                return
            }
            presentExitConfirmationIfNeeded(action: action)
        }

        private func presentExitConfirmationIfNeeded(action: @escaping () -> Void) {
            guard !isPresentingExitConfirmation else { return }
            guard let rootViewController = mainWindow?.rootViewController else {
                action()
                return
            }

            isPresentingExitConfirmation = true

            let alert = AlertViewController(
                title: String(localized: "Exit"),
                message: String(localized: "Exiting now will interrupt the running conversation."),
            ) { [weak self] context in
                context.addAction(title: String(localized: "Cancel")) {
                    self?.isPresentingExitConfirmation = false
                    context.dispose()
                }
                context.addAction(title: String(localized: "Exit"), attribute: .accent) {
                    self?.isPresentingExitConfirmation = false
                    context.dispose {
                        action()
                    }
                }
            }

            rootViewController.topMostController.present(alert, animated: true)
        }
    #endif
}

func terminateApplication() -> Never {
    #if targetEnvironment(macCatalyst)
        exit(0)
    #else
        UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
        Task.detached {
            try? await Task.sleep(for: .seconds(1))
            exit(0)
        }
        sleep(5)
        fatalError()
    #endif
}

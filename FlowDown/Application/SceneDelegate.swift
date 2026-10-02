//
//  SceneDelegate.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import Combine
import ConfigurableKit
import FlowDownModelExchange
import MLX
import Storage
import UIKit

@objc(SceneDelegate)
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    var cancellables = Set<AnyCancellable>()
    lazy var mainController = MainController()

    func scene(
        _ scene: UIScene,
        willConnectTo _: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions,
    ) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        #if targetEnvironment(macCatalyst)
            if let titlebar = windowScene.titlebar {
                titlebar.titleVisibility = .hidden
                titlebar.toolbar = nil
            }
            windowScene.sizeRestrictions?.minimumSize = CGSize(width: 650, height: 650)
        #endif
        let window = UIWindow(windowScene: windowScene)
        defer {
            window.makeKeyAndVisible()
            self.window = window
        }

        if RecoveryMode.isActivated {
            window.rootViewController = RecoveryModeViewController()
        } else {
            window.rootViewController = mainController

            ModelExchangeCoordinator.shared.registerPresenter(mainController)
            UIUserInterfaceStyle.reapplyConfiguredStyle()
            #if targetEnvironment(macCatalyst)
                confirmClosureWhileConversationsRun(in: windowScene)
            #endif

            for urlContext in connectionOptions.urlContexts {
                handleIncomingURL(urlContext.url)
            }
        }
    }

    func scene(_: UIScene, openURLContexts contexts: Set<UIOpenURLContext>) {
        guard !RecoveryMode.isActivated else { return }

        for urlContext in contexts {
            handleIncomingURL(urlContext.url)
        }
    }

    func sceneWillEnterForeground(_: UIScene) {
        guard !RecoveryMode.isActivated else { return }
        UIUserInterfaceStyle.reapplyConfiguredStyle()
    }

    /// Pairs with `sceneWillResignActive`. A resign does not always reach the
    /// background (Control Center, a system alert, Cmd+Tab on Mac), so the
    /// restore must run on become-active, not on will-enter-foreground.
    func sceneDidBecomeActive(_: UIScene) {
        guard !RecoveryMode.isActivated else { return }
        MLX.GPU.onApplicationBecomeActivate()
        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 16.2, *) {
                LiveActivityService.shared.appDidEnterForeground()
            }
        #endif
    }

    func sceneWillResignActive(_: UIScene) {
        guard !RecoveryMode.isActivated else { return }
        MLX.GPU.onApplicationResignActivate()
        #if canImport(ActivityKit) && os(iOS) && !targetEnvironment(macCatalyst)
            if #available(iOS 16.2, *) {
                LiveActivityService.shared.appWillEnterBackground()
            }
        #endif
    }

    func sceneDidDisconnect(_: UIScene) {
        #if targetEnvironment(macCatalyst)
            guard !RecoveryMode.isActivated else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(200))
                let remainingWindowScenes = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                guard remainingWindowScenes.isEmpty else { return }
                exit(0)
            }
        #endif
    }
}

#if targetEnvironment(macCatalyst)
    private extension SceneDelegate {
        /// The window's close button and Dock > Quit go through AppKit and never
        /// reach `AppDelegate.performClose(_:)` or `terminate(_:)`, so they skip
        /// the exit confirmation those show. From macOS 27 the system shows the
        /// scene's `closureConfirmation` on both paths, so keep it set while a
        /// conversation runs.
        func confirmClosureWhileConversationsRun(in windowScene: UIWindowScene) {
            #if compiler(>=6.4)
                guard #available(iOS 27.0, macCatalyst 27.0, *) else { return }
                ConversationSessionManager.shared.executingSessionsPublisher
                    .map { !$0.isEmpty }
                    .removeDuplicates()
                    .receive(on: DispatchQueue.main)
                    .sink { [weak windowScene] isExecuting in
                        windowScene?.closureConfirmation = isExecuting
                            ? UISceneClosureConfirmation(
                                title: String(localized: "Exit"),
                                message: String(localized: "Exiting now will interrupt the running conversation."),
                                actions: [],
                            )
                            : nil
                    }
                    .store(in: &cancellables)
            #endif
        }
    }
#endif

private extension SceneDelegate {
    func handleIncomingURL(_ url: URL) {
        switch url.scheme {
        case "file":
            switch url.pathExtension {
            case "fdmodel", "plist":
                importModel(from: url)
            case "fdtemplate":
                importTemplate(from: url)
            case "fdmcp":
                importMCPServer(from: url)
            default: break // dont know how
            }
        case "flowdown":
            handleFlowDownURL(url)
        default:
            break
        }
    }

    func importModel(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let model = try ModelManager.shared.importCloudModel(at: url)
            mainController.queueBootMessage(
                text: "Successfully imported model \(model.auxiliaryIdentifier)",
            )
        } catch {
            mainController.queueBootMessage(
                text: "Failed to import model: \(error.localizedDescription)",
            )
        }
    }

    func importTemplate(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let data = try Data(contentsOf: url)
            Task { @MainActor in
                do {
                    let template = try ChatTemplateManager.shared.importTemplate(from: data)
                    mainController.queueBootMessage(text: "Successfully imported \(template.name)")
                } catch {
                    Logger.app.errorFile("failed to import template from URL: \(url), error: \(error)")
                    mainController.queueBootMessage(
                        text: "Failed to import template: \(error.localizedDescription)",
                    )
                }
            }
        } catch {
            Logger.app.errorFile("failed to import template from URL: \(url), error: \(error)")
            mainController.queueBootMessage(
                text: "Failed to import template: \(error.localizedDescription)",
            )
        }
    }

    func importMCPServer(from url: URL) {
        _ = url.startAccessingSecurityScopedResource()
        defer { url.stopAccessingSecurityScopedResource() }
        try? FileManager.default.startDownloadingUbiquitousItem(at: url)
        do {
            let data = try Data(contentsOf: url)
            Task { @MainActor in
                do {
                    let server = try MCPService.shared.importServer(from: data)
                    let serverName = if let serverUrl = URL(string: server.endpoint), let host = serverUrl.host {
                        host
                    } else if !server.name.isEmpty {
                        server.name
                    } else {
                        String(localized: "MCP Server")
                    }
                    mainController.queueBootMessage(
                        text: "Successfully imported MCP server \(serverName)",
                    )
                } catch {
                    Logger.app.errorFile("failed to import MCP server from URL: \(url), error: \(error)")
                    mainController.queueBootMessage(
                        text: "Failed to import MCP server: \(error.localizedDescription)",
                    )
                }
            }
        } catch {
            Logger.app.errorFile("failed to import MCP server from URL: \(url), error: \(error)")
            mainController.queueBootMessage(
                text: "Failed to import MCP server: \(error.localizedDescription)",
            )
        }
    }

    func handleFlowDownURL(_ url: URL) {
        Logger.app.infoFile("handling incoming message: \(url)")
        if let handled = ModelExchangeAPI.resolveInputScheme(url) {
            if handled == false {
                mainController.queueBootMessage(
                    text: "Model exchange request failed validation",
                )
            }
            return
        }
        guard url.host() == "new" else { return }
        handleNewMessageURL(url)
    }

    func handleNewMessageURL(_ url: URL) {
        guard let message = Self.newConversationMessage(from: url) else { return }
        mainController.queueNewConversation(text: message, shouldSend: !message.isEmpty)
    }
}

extension SceneDelegate {
    /// Reads the message of a `flowdown://new/<message>` link.
    ///
    /// `pathComponents` is already decoded, so decoding it again drops a
    /// message with a bare "%" and rewrites literal "%xx" text. Decode the
    /// raw path once instead, which also keeps any "/" in the message.
    static func newConversationMessage(from url: URL) -> String? {
        guard url.pathComponents.count >= 2 else { return nil }
        let encodedMessage = String(url.path(percentEncoded: true).dropFirst())
        let message = encodedMessage.removingPercentEncoding ?? encodedMessage
        return message.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

//
//  Indicator.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/29/25.
//

import AlertController
import Foundation
import SafariServices
import SPIndicator
import UIKit

enum Indicator {
    private static func ensureMainThread(_ execute: @escaping () -> Void) {
        if Thread.isMainThread {
            execute()
        } else {
            Task { @MainActor in
                execute()
            }
        }
    }

    static func present(
        title: String.LocalizationValue,
        message: String.LocalizationValue? = nil,
        preset: SPIndicatorIconPreset = .done,
        referencingView: UIView? = nil,
    ) {
        ensureMainThread {
            let titleString = String(localized: title)
            let messageString = message.map { String(localized: $0) }
            let view = SPIndicatorView(title: titleString, message: messageString, preset: preset)
            if let window = referencingView as? UIWindow {
                view.presentWindow = window
            } else if let window = referencingView?.window {
                view.presentWindow = window
            }
            view.present(haptic: .success, completion: nil)
        }
    }

    typealias CompletionDismissRequest = @MainActor () async -> Void
    typealias CompletionCallback = (CompletionDismissRequest) async -> Void
    typealias ExecutionWithCompletion = (CompletionCallback) async throws -> Void
    typealias ProgressCallback = @MainActor (String) -> Void
    typealias ExecutionWithProgressCompletion = (@escaping ProgressCallback, CompletionCallback) async throws -> Void

    static func progress(
        title: String.LocalizationValue,
        message: String.LocalizationValue? = nil,
        controller: UIViewController,
        completionExecutor: @escaping ExecutionWithCompletion,
    ) {
        Task { @MainActor in
            let titleString = String(localized: title)
            let messageString = if let message { String(localized: message) } else { String("") }
            let alert = AlertProgressIndicatorViewController(
                title: titleString,
                message: messageString,
            )
            controller.present(alert, animated: true) {
                Task.detached(priority: .userInitiated) {
                    await runProgressTask(on: controller, alert: alert) { _, completion in
                        try await completionExecutor(completion)
                    }
                }
            }
        }
    }

    static func progress(
        title: String.LocalizationValue,
        message: String.LocalizationValue? = nil,
        controller: UIViewController,
        completionExecutor: @escaping ExecutionWithProgressCompletion,
    ) {
        Task { @MainActor in
            let titleString = String(localized: title)
            let messageString = if let message { String(localized: message) } else { String("") }
            let alert = AlertProgressIndicatorViewController(
                title: titleString,
                message: messageString,
            )
            controller.present(alert, animated: true) {
                Task.detached(priority: .userInitiated) {
                    await runProgressTask(on: controller, alert: alert) { progress, completion in
                        try await completionExecutor(progress, completion)
                    }
                }
            }
        }
    }

    static func present(_ url: URL, referencedView: UIView?) {
        #if targetEnvironment(macCatalyst)
            UIApplication.shared.open(url)
        #else
            let safari = SFSafariViewController(url: url)
            safari.modalPresentationStyle = .formSheet
            safari.preferredContentSize = CGSize(width: 555, height: 555)
            referencedView?.parentViewController?.present(safari, animated: true)
        #endif
    }

    private static func runProgressTask(
        on controller: UIViewController,
        alert: AlertProgressIndicatorViewController,
        operation: @escaping @Sendable (@escaping ProgressCallback, CompletionCallback) async throws -> Void,
    ) async {
        var capturedError: Error?
        let progress: ProgressCallback = { message in
            alert.progressContext.purpose(message: message)
        }
        let completion: CompletionCallback = { @MainActor callerCompletionItem in
            await alert.dismiss()
            if let error = capturedError {
                let errorAlert = AlertViewController(
                    title: "Error",
                    message: String(localized: "An error occurred: \(error.localizedDescription)"),
                ) { context in
                    context.allowSimpleDispose()
                    context.addAction(title: "OK", attribute: .accent) {
                        context.dispose()
                    }
                }
                controller.present(errorAlert, animated: true)
            }
            await callerCompletionItem()
        }
        do {
            try await operation(progress, completion)
        } catch {
            capturedError = error
            await completion {}
        }
    }
}

private extension UIViewController {
    @MainActor
    func dismiss() async {
        await withCheckedContinuation { cont in
            dismiss(animated: true) {
                cont.resume(returning: ())
            }
        }
    }
}

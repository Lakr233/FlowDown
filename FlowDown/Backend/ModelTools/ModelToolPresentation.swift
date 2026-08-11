//
//  ModelToolPresentation.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import AlertController
import Foundation
import UIKit

/// Failures reported back to the model when a tool call cannot complete.
/// Every tool used to spell out the same `NSError` inline, so the domain and
/// code live here instead.
enum ModelToolError {
    static func failure(_ message: String) -> NSError {
        NSError(domain: String(localized: "Tool"), code: -1, userInfo: [
            NSLocalizedDescriptionKey: message,
        ])
    }

    static func userCancelled() -> NSError {
        failure(String(localized: "User cancelled the operation."))
    }
}

/// Presenting a tool dialog is the same dance everywhere: refuse when another
/// dialog already owns the screen, then fail the awaiting continuation if the
/// alert never made it on screen.
enum ModelToolPresentation {
    @MainActor
    static func present(
        _ alert: AlertViewController,
        on controller: UIViewController,
        continuation: CheckedContinuation<String, any Swift.Error>,
        displayFailure: String,
    ) {
        guard controller.presentedViewController == nil else {
            continuation.resume(throwing: ModelToolError.failure(
                String(localized: "Tool execution failed: authorization dialog is already presented."),
            ))
            return
        }

        controller.present(alert, animated: true) {
            guard alert.isVisible else {
                continuation.resume(throwing: ModelToolError.failure(displayFailure))
                return
            }
        }
    }
}

extension ModelTool {
    /// Tool arguments always arrive as a JSON object encoded in a string.
    func decodeArguments(_ input: String) -> [String: Any]? {
        guard let data = input.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    /// The controller a tool presents its dialogs from.
    func anchorController(for view: UIView) async throws -> UIViewController {
        guard let controller = await view.parentViewController else {
            throw ModelToolError.failure(String(localized: "Could not find view controller"))
        }
        return controller
    }
}

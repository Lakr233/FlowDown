//
//  UIViewController.swift
//  FlowDown
//
//  Created by qaq on 8/12/2025.
//

import AlertController
import UIKit

extension UIViewController {
    /// Presents the standard Cancel / accent-Delete confirmation alert.
    /// Parameters stay `String.LocalizationValue` so Xcode keeps extracting
    /// the call-site literals into Localizable.xcstrings.
    func presentDeleteConfirmation(
        title: String.LocalizationValue,
        message: String.LocalizationValue,
        onConfirm: @escaping @MainActor () -> Void,
    ) {
        let alert = AlertViewController(title: title, message: message) { context in
            context.addAction(title: "Cancel") {
                context.dispose()
            }
            context.addAction(title: "Delete", attribute: .accent) {
                context.dispose { onConfirm() }
            }
        }
        present(alert, animated: true)
    }

    /// Returns the currently visible controller from this point in the hierarchy.
    var topMostController: UIViewController {
        var current: UIViewController = self

        while true {
            if let presentedViewController = current.presentedViewController {
                current = presentedViewController
                continue
            }

            let possibleSelectors: [Selector] = [
                NSSelectorFromString("topViewController"),
                NSSelectorFromString("visibleViewController"),
                NSSelectorFromString("contentViewController"),
                NSSelectorFromString("rootViewController"),
                NSSelectorFromString("selectedViewController"),
                NSSelectorFromString("detailViewController"),
            ]
            for selector in possibleSelectors {
                guard current.responds(to: selector),
                      let next = current.perform(selector)?
                      .takeUnretainedValue()
                      as? UIViewController
                else {
                    continue
                }
                current = next
            }

            for child in current.children where child.view.frame == current.view.frame {
                current = child
            }

            break
        }

        return current
    }
}

// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeFlow.swift, adapted from
// Irisin's welcome navigation). FlowDown's pages, its completion record and
// its Mac container differ.
//
//  WelcomeFlow.swift
//  FlowDown
//

import AlertController
import SnapKit
import UIKit

/// The onboarding pages in one navigation stack inside a form sheet:
/// Welcome, Choose a Model, Your Data, Before You Start. Only Get Started on
/// the last page records the welcome as seen.
@MainActor
final class WelcomeFlow {
    static let preferredSize = CGSize(width: 520, height: 620)

    private weak var navigation: UINavigationController?
    /// The controller that was presented: the navigation controller, or on
    /// Mac the alert container around it.
    private weak var container: UIViewController?
    private var finished = false
    private let onFinish: () -> Void

    private init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }

    static func present(from presenter: UIViewController, onFinish: @escaping () -> Void = {}) {
        let flow = WelcomeFlow(onFinish: onFinish)
        // The pages hold the flow; the flow holds only weak references back.
        let welcome = WelcomePageViewController {
            flow.showModels()
        }
        welcome.navigationItem.largeTitleDisplayMode = .never

        let navigation = WelcomeNavigationController(rootViewController: welcome)
        navigation.isModalInPresentation = true
        navigation.navigationBar.prefersLargeTitles = true
        navigation.view.backgroundColor = WelcomeStyle.background
        navigation.view.tintColor = WelcomeStyle.accent
        navigation.navigationBar.tintColor = WelcomeStyle.accent
        flow.navigation = navigation

        #if targetEnvironment(macCatalyst)
            let container = AlertBaseController(
                rootViewController: navigation,
                preferredWidth: preferredSize.width,
                preferredHeight: preferredSize.height,
            )
            container.shouldDismissWhenTappedAround = false
            container.shouldDismissWhenEscapeKeyPressed = false
            container.isModalInPresentation = true
        #else
            let container: UIViewController = navigation
            navigation.modalTransitionStyle = .coverVertical
            navigation.modalPresentationStyle = .formSheet
            navigation.preferredContentSize = preferredSize
        #endif
        flow.container = container
        presenter.present(container, animated: true)
    }

    func showModels() {
        push(WelcomeModelPage(flow: self))
    }

    func showData() {
        push(WelcomeNoticePage.data(flow: self))
    }

    func showCaution() {
        push(WelcomeNoticePage.caution(flow: self))
    }

    private func push(_ page: UIViewController) {
        let animated = !UIAccessibility.isReduceMotionEnabled
        // The welcome page hides the bar. Show it before the push, so the
        // next page lays out under it from the start instead of sliding its
        // first rows beneath it.
        navigation?.setNavigationBarHidden(false, animated: animated)
        navigation?.pushViewController(page, animated: animated)
    }

    func finish() {
        guard !finished else { return }
        finished = true
        WelcomeExperience.markPresented()
        onFinish()
        container?.dismiss(animated: !UIAccessibility.isReduceMotionEnabled)
    }
}

/// Keeps the title row horizontal on iPhone Duo's outer display, as
/// Settings does: a sheet's bar otherwise stands vertically over the
/// trailing edge, beside the page's own action bar.
final class WelcomeNavigationController: UINavigationController {
    #if compiler(>=6.4.2) && !targetEnvironment(macCatalyst)
        @available(iOS 27.1, *)
        override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
            .disabled
        }

        @available(iOS 27.1, *)
        override var childForPreferredVerticalBarBehavior: UIViewController? {
            nil
        }
    #endif
}

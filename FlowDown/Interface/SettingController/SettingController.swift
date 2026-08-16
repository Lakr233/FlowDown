//
//  SettingController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2025/1/2.
//

import AlertController
import UIKit

#if targetEnvironment(macCatalyst)
    class SettingController: AlertBaseController {
        override open var keyCommands: [UIKeyCommand]? {
            [
                UIKeyCommand(
                    title: NSLocalizedString("Back", comment: ""),
                    action: #selector(escapePressed), // escape
                    input: "\u{1b}",
                    modifierFlags: [],
                    propertyList: nil,
                ),
            ]
        }

        var content: NavigationController! = .init()

        private var sheetSizingConstraints: [NSLayoutConstraint] = []

        override convenience init() {
            let nav = NavigationController()
            // No fixed size up front: the sheet sizes itself against the
            // window it is actually presented into, read once it is there.
            self.init(
                rootViewController: nav,
                preferredWidth: nil,
                preferredHeight: nil,
            )

            content = nav
            shouldDismissWhenTappedAround = false
            shouldDismissWhenEscapeKeyPressed = true
        }

        override func viewWillLayoutSubviews() {
            super.viewWillLayoutSubviews()
            // Size against the window the sheet is actually presented into,
            // refreshing on every pass so a live window resize is followed.
            guard let window = view.window else { return }
            let size = ModalWindowSize.resolve(in: window)
            if sheetSizingConstraints.isEmpty {
                let constraints = [
                    contentView.widthAnchor.constraint(equalToConstant: size.width),
                    contentView.heightAnchor.constraint(equalToConstant: size.height),
                ]
                NSLayoutConstraint.activate(constraints)
                sheetSizingConstraints = constraints
            } else {
                sheetSizingConstraints[0].constant = size.width
                sheetSizingConstraints[1].constant = size.height
            }
        }

        override func contentViewDidLoad() {
            super.contentViewDidLoad()
            contentView.backgroundColor = .background
        }

        @objc override func escapePressed() {
            guard presentedViewController == nil else { return }
            if content.viewControllers.count > 1 {
                content.popViewController(animated: true)
            } else {
                dismiss(animated: true)
            }
        }

        class NavigationController: UINavigationController {
            let content = SettingContent()

            init() {
                super.init(rootViewController: content)
                navigationBar.prefersLargeTitles = false
            }

            @available(*, unavailable)
            required init?(coder _: NSCoder) {
                fatalError()
            }

            override func viewDidLoad() {
                super.viewDidLoad()
                view.alpha = 0
            }

            override func viewWillAppear(_ animated: Bool) {
                super.viewWillAppear(animated)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(100))
                    UIView.animate(withDuration: 0.25) {
                        self.view.alpha = 1
                    }
                }
            }
        }
    }
#else
    class SettingController: UINavigationController {
        init() {
            super.init(rootViewController: SettingContent())
            navigationBar.prefersLargeTitles = false
            modalPresentationStyle = .formSheet
            modalTransitionStyle = .coverVertical
            preferredContentSize = .init(width: 550, height: 550 - navigationBar.height)
            view.backgroundColor = .background
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
#endif

extension SettingController {
    enum EntryPage {
        case general
        case inference
        case chatTemplateEditor(templateIdentifier: ChatTemplate.ID)
        case modelManagement
        case modelEditor(model: ModelManager.ModelIdentifier)
        case tools
        case mcp
        case memory
        case dataControl
        case permissionList
        case contactUs
    }

    private static var nextEntryPage: EntryPage?

    static func setNextEntryPage(_ page: EntryPage) {
        nextEntryPage = page
    }

    static func getNextEntryPage() -> EntryPage? {
        if let ret = nextEntryPage {
            nextEntryPage = nil
            return ret
        }
        return nil
    }
}

//
//  SyncScopePage.swift
//  FlowDown
//
//  Created by AI on 2025/10/22.
//

import AlertController
import ConfigurableKit
import Storage
import UIKit

final class SyncScopePage: StackScrollController {
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        title = String(localized: "Sync Scope")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
    }

    override func setupContentViews() {
        super.setupContentViews()

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(
                header: "Syncing Scope",
            ),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        addGroupToggle(
            icon: "text.bubble",
            title: "Conversations, Messages, Attachments",
            desc: "Sync chats and their messages and files.",
            group: .conversations,
        )

        addGroupToggle(
            icon: "brain.head.profile",
            title: "Memory",
            desc: "Sync your AI memory entries.",
            group: .memory,
        )

        addGroupToggle(
            icon: "rectangle.3.group.bubble.left",
            title: "MCP Servers",
            desc: "Sync configured MCP connections.",
            group: .mcp,
        )

        addGroupToggle(
            icon: "icloud",
            title: "Models",
            desc: "Sync cloud model configurations.",
            group: .models,
        )

        addGroupToggle(
            icon: "doc.text.image",
            title: "Chat Templates",
            desc: "Sync your saved chat templates across devices.",
            group: .templates,
        )

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(
                header: "Shortcuts",
            ),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let refreshAction = ConfigurableObject(
            icon: "arrow.clockwise.icloud",
            title: "Fetch Updates Now",
            explain: "This will request the latest changes from iCloud immediately, but depending on the amount of data and network conditions, it may take some time to complete",
            ephemeralAnnotation: .action { controller in
                guard SyncEngine.isCloudSyncSupported else {
                    let alert = AlertViewController(
                        title: "Unavailable",
                        message: "iCloud sync is not available on this iOS version.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) { context.dispose() }
                    }
                    controller.present(alert, animated: true)
                    return
                }

                guard SyncEngine.isSyncEnabled else {
                    let alert = AlertViewController(
                        title: "Error Occurred",
                        message: "iCloud synchronization is not enabled. You have to enable iCloud sync in settings before fetching updates.",
                    ) { context in
                        context.allowSimpleDispose()
                        context.addAction(title: "OK", attribute: .accent) { context.dispose() }
                    }
                    controller.present(alert, animated: true)
                    return
                }

                Indicator.progress(title: "Refreshing...", controller: controller) { completion in
                    try await syncEngine.fetchChanges()
                    await completion {
                        let alert = AlertViewController(
                            title: "Update Requested",
                            message: "The request to fetch updates has been sent. Depending on the amount of data, it may take some time to complete.",
                        ) { context in
                            context.allowSimpleDispose()
                            context.addAction(title: "OK", attribute: .accent) {
                                context.dispose()
                            }
                        }
                        controller.present(alert, animated: true)
                    }
                }
            },
        ).createView()
        stackView.addArrangedSubviewWithMargin(refreshAction)
        stackView.addArrangedSubview(SeparatorView())
    }
}

extension SyncScopePage {
    func addGroupToggle(icon: String, title: String.LocalizationValue, desc: String.LocalizationValue, group: SyncPreferences.Group) {
        let toggle = ConfigurableToggleActionView()
        toggle.configure(icon: UIImage(systemName: icon))
        toggle.configure(title: title)
        toggle.configure(description: desc)
        toggle.boolValue = SyncPreferences.isGroupEnabled(group)
        toggle.actionBlock = { value in
            SyncPreferences.setGroup(group, enabled: value)
        }
        stackView.addArrangedSubviewWithMargin(toggle)
        stackView.addArrangedSubview(SeparatorView())
    }
}

//
//  SettingContent+Support.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import ConfigurableKit
import Storage
import UIKit

extension SettingController.SettingContent {
    class SupportController: StackScrollController {
        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Contact Us")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
        }

        override func setupContentViews() {
            super.setupContentViews()

            stackView.addArrangedSubview(SeparatorView())

            for section in settingSections {
                if !String(localized: section.title).isEmpty {
                    stackView.addArrangedSubviewWithMargin(
                        ConfigurableSectionHeaderView().with(header: section.title),
                    ) { $0.bottom /= 2 }
                    stackView.addArrangedSubview(SeparatorView())
                }
                for object in section.objects {
                    stackView.addArrangedSubviewWithMargin(object.createView())
                    stackView.addArrangedSubview(SeparatorView())
                }
            }
        }
    }
}

extension SettingController.SettingContent.SupportController {
    typealias SettingSection = (
        title: String.LocalizationValue,
        objects: [ConfigurableObject],
    )
    var documentObject: SettingSection {
        (
            title: "Read Documents",
            objects: [
                ConfigurableObject(
                    icon: "safari",
                    title: "Open Documentation",
                    explain: "We provided a comprehensive documentation to help you understand how to use this app effectively.",
                    ephemeralAnnotation: .link(
                        title: "Open...",
                        url: URL(string: "https://flowdown.ai/docs/")!,
                    ),
                ),
            ],
        )
    }

    var contactObject: SettingSection {
        (
            title: "Contact Us",
            objects: [
                ConfigurableObject(
                    icon: "envelope",
                    title: "Email",
                    explain: "Send us an email.",
                    ephemeralAnnotation: .link(
                        title: "Open...",
                        url: URL(string: "mailto:flowdownapp@qaq.wiki")!,
                    ),
                ),
                ConfigurableObject(
                    icon: "safari",
                    title: "\("GitHub")",
                    explain: "Leave a message on GitHub issue.",
                    ephemeralAnnotation: .link(
                        title: "Open...",
                        url: URL(string: "https://github.com/Lakr233/FlowDown/issues")!,
                    ),
                ),
                ConfigurableObject(
                    icon: "bubble.left",
                    title: "\("Discord")",
                    explain: "Join our Discord server.",
                    ephemeralAnnotation: .link(
                        title: "Open...",
                        url: URL(string: "https://discord.gg/UHKMRyJcgc")!,
                    ),
                ),
                ConfigurableObject(
                    icon: "doc.richtext",
                    title: "View Logs",
                    explain: "Inspect recent application logs for troubleshooting.",
                    ephemeralAnnotation: .action { controller in
                        controller.navigationController?.pushViewController(LogViewerController(), animated: true)
                    },
                ),
            ],
        )
    }

    var openSourceObject: SettingSection {
        (
            title: "Software Resources",
            objects: [
                ConfigurableObject(
                    icon: "flag.filled.and.flag.crossed",
                    title: "Open Source Licenses",
                    explain: "These are the open-source licenses for the frameworks used in this app.",
                    ephemeralAnnotation: .action { controller in
                        controller.navigationController?.pushViewController(
                            OpenSourceLicenseController(),
                            animated: true
                        )
                    },
                ),
            ],
        )
    }

    var agreementsObject: SettingSection {
        (
            title: "Agreements",
            objects: [
                ConfigurableObject(
                    icon: "lock",
                    title: "Privacy Policy",
                    explain: "Tells you how we handle your data.",
                    ephemeralAnnotation: .action { controller in
                        controller.navigationController?.pushViewController(PrivacyPolicyController(), animated: true)
                    },
                ),
            ],
        )
    }

    var settingSections: [SettingSection] {
        [
            documentObject,
            contactObject,
            agreementsObject,
            openSourceObject,
        ]
    }
}

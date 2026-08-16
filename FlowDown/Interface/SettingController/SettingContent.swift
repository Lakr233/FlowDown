//
//  SettingContent.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/24/25.
//

import ConfigurableKit
import UIKit

extension SettingController {
    class SettingContent: StackScrollController {
        let closeButton: ImageCircleButton = if #available(iOS 26, macCatalyst 26, *) {
            .init(name: "xmark", distinctStyle: .none, inset: 8)
        } else {
            .init(name: "xmark", distinctStyle: .border, inset: 8)
        }

        nonisolated(unsafe) let objects: [ConfigurableObject] = [
            .init(
                icon: "gear",
                title: "General",
                explain: "Change the behavior of the application, adjust text sizes, tuning editor behavior.",
                ephemeralAnnotation: .page { GeneralController() },
            ),
            .init(
                icon: "bolt",
                title: "Inference",
                explain: "Configure global prompt, adjust parameters when inferencing.",
                ephemeralAnnotation: .page { InferenceController() },
            ),
            .init(
                icon: "doc.text.magnifyingglass",
                title: "Model",
                explain: "Manage language model providers or download local models.",
                ephemeralAnnotation: .page { ModelController() },
            ),
            .init(
                icon: "hammer",
                title: "Tools",
                explain: "Configure tool settings, choose search engine for internet searches, adding custom tools.",
                ephemeralAnnotation: .page { ToolsController() },
            ),
            .init(
                icon: "moon.stars",
                title: "Memory",
                explain: "Manage AI memory tools and stored conversation memories.",
                ephemeralAnnotation: .page { MemoryController() },
            ),
            .init(
                icon: "lock.shield",
                title: "Data",
                explain: "Get control of your data, configure cloud sync, export database or reset the app.",
                ephemeralAnnotation: .page { DataControlController() },
            ),
            .init(
                icon: "key",
                title: "Permission",
                explain: "Manage permissions for the application. Your privacy is important to us.",
                ephemeralAnnotation: .page { PermissionController() },
            ),
            .init(
                icon: "envelope",
                title: "Support",
                explain: "Have any questions or just wanna keep in touch? Contact us.",
                ephemeralAnnotation: .page { SupportController() },
            ),
        ]

        init() {
            super.init(nibName: nil, bundle: nil)
            title = String(localized: "Settings")
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .background
            #if targetEnvironment(macCatalyst)
                scrollView.scrollIndicatorInsets = .init(top: 8, left: 0, bottom: 8, right: 0)
            #endif
            navigationController?.setNavigationBarHidden(true, animated: false)
        }

        override func setupContentViews() {
            super.setupContentViews()

            if #available(iOS 26, macCatalyst 26, *) {
                navigationItem.rightBarButtonItem = .init(customView: closeButton)
            } else {
                // Float the button above the scrolling content instead of
                // scrolling away with the first row — the reader has to be
                // able to close the sheet from wherever they are in it.
                view.addSubview(closeButton)
                closeButton.snp.makeConstraints { make in
                    make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(8)
                    make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing).offset(-8)
                    make.width.height.equalTo(32)
                }
            }
            closeButton.actionBlock = { [weak self] in
                self?.navigationController?.dismiss(animated: true, completion: nil)
            }

            stackView.addArrangedSubviewWithMargin(SettingHeaderView())
            stackView.addArrangedSubview(SeparatorView())

            for object in objects {
                let view = object.createView()
                stackView.addArrangedSubviewWithMargin(view)
                stackView.addArrangedSubview(SeparatorView())
            }

            stackView.addArrangedSubviewWithMargin(SettingFooterView())
            stackView.addArrangedSubviewWithMargin(UIView())
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            if #available(iOS 26, macCatalyst 26, *) {
                // nope, we dont hide it
                if let nav = navigationController,
                   nav.isNavigationBarHidden
                {
                    nav.setNavigationBarHidden(false, animated: animated)
                }

            } else {
                navigationController?.setNavigationBarHidden(true, animated: animated)
            }
            scrollView.flashScrollIndicators()
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if #available(iOS 26, macCatalyst 26, *) {
                // nope, we dont hide it
                if let nav = navigationController,
                   nav.isNavigationBarHidden
                {
                    nav.setNavigationBarHidden(false, animated: animated)
                }
            } else {
                if let nav = navigationController,
                   nav.viewControllers.count > 1,
                   nav.isNavigationBarHidden
                {
                    nav.setNavigationBarHidden(false, animated: animated)
                }
            }
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)

            if let entry = SettingController.getNextEntryPage(),
               let controller = entry.controller
            {
                navigationController?.pushViewController(controller, animated: true)
            }

            view.window?.firstResponder()?.resignFirstResponder()
        }
    }
}

extension SettingController.EntryPage {
    var controller: UIViewController? {
        switch self {
        case .general:
            return SettingController.SettingContent.GeneralController()
        case .inference:
            return SettingController.SettingContent.InferenceController()
        case let .chatTemplateEditor(templateIdentifier):
            return ChatTemplateEditorController(templateIdentifier: templateIdentifier)
        case .modelManagement:
            return SettingController.SettingContent.ModelController()
        case .tools:
            return SettingController.SettingContent.ToolsController()
        case .mcp:
            return SettingController.SettingContent.MCPController()
        case .memory:
            return SettingController.SettingContent.MemoryController()
        case .dataControl:
            return SettingController.SettingContent.DataControlController()
        case .permissionList:
            return SettingController.SettingContent.PermissionController()
        case .contactUs:
            return SettingController.SettingContent.SupportController()
        case let .modelEditor(modelIdentifier):
            if let localModel = ModelManager.shared.localModel(identifier: modelIdentifier) {
                return LocalModelEditorController(identifier: localModel.id)
            }
            if let cloudModel = ModelManager.shared.cloudModel(identifier: modelIdentifier) {
                return CloudModelEditorController(identifier: cloudModel.id)
            }
            return nil
        }
    }
}

extension SettingController.SettingContent {
    class SettingHeaderView: UIView {
        let iconImageView = UIImageView().with {
            $0.image = .avatar
            $0.contentMode = .scaleAspectFill
            $0.layer.cornerRadius = 16
            $0.layer.cornerCurve = .continuous
            $0.layerBorderWidth = 1
            $0.layerBorderColor = .systemGray4.withAlphaComponent(0.5)
            $0.clipsToBounds = true
        }

        let label = UILabel().with {
            $0.text = String(localized: "Settings")
            $0.numberOfLines = 0
            $0.textAlignment = .center
            $0.font = .preferredFont(forTextStyle: .body).bold
            $0.textColor = .label
        }

        let descriptionLabel = UILabel().with {
            $0.text = String(localized: "Change application behavior, manage language model providers, and get control of your data.")
            $0.numberOfLines = 0
            $0.textAlignment = .center
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .label
        }

        init() {
            super.init(frame: .zero)

            addSubview(iconImageView)
            iconImageView.snp.makeConstraints { make in
                make.top.equalToSuperview()
                make.width.height.equalTo(64)
                make.centerX.equalToSuperview()
            }

            addSubview(label)
            label.snp.makeConstraints { make in
                make.top.equalTo(iconImageView.snp.bottom).offset(16)
                make.centerX.equalToSuperview()
                make.width.equalToSuperview()
            }

            addSubview(descriptionLabel)
            descriptionLabel.snp.makeConstraints { make in
                make.top.equalTo(label.snp.bottom).offset(8)
                make.centerX.equalToSuperview()
                make.width.equalToSuperview()
                make.bottom.equalToSuperview()
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}

extension SettingController.SettingContent {
    class SettingFooterView: UIView {
        let stackView = UIStackView().with {
            $0.axis = .vertical
            $0.alignment = .center
            $0.spacing = 8
        }

        let versionLabel = UILabel().with {
            let version = String(AnchorVersion.version)
            let build = String(AnchorVersion.build)
            let text = String(format: String(localized: "Version %@ (%@)"), version, build)
            #if DEBUG
                let finalText = text + " 🐦"
            #else
                let finalText = text
            #endif
            $0.text = finalText
            $0.font = .preferredFont(forTextStyle: .caption2)
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 1
        }

        let buildTimeLabel = UILabel().with {
            $0.text = BuildInfo.buildTime
            $0.font = .preferredFont(forTextStyle: .caption2).monospaced
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 1
        }

        let commitLabel = UILabel().with {
            let commitID = BuildInfo.commitID
            let displayCommit = commitID.isEmpty ? "N/A" : String(commitID)
            $0.text = displayCommit
            $0.font = .preferredFont(forTextStyle: .caption2).monospaced
            $0.textColor = .tertiaryLabel
            $0.textAlignment = .center
            $0.numberOfLines = 1
        }

        init() {
            super.init(frame: .zero)

            addSubview(stackView)
            stackView.addArrangedSubview(versionLabel)
            stackView.addArrangedSubview(buildTimeLabel)
            stackView.addArrangedSubview(commitLabel)

            stackView.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }
    }
}

extension StackScrollController {
    func setupConfigurableObjectViews(from objects: [ConfigurableObject]) {
        for (idx, object) in objects.enumerated() {
            let view = object.createView()
            stackView.addArrangedSubviewWithMargin(view)
            if idx < objects.count - 1 { stackView.addArrangedSubview(SeparatorView()) }
        }
    }
}

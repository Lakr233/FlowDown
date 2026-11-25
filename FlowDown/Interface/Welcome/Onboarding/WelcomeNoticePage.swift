// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeCautionController.swift,
// itself copied from Irisin). The same layout serves FlowDown's Your Data
// page and its Before You Start page; only the symbol, text and action differ.
//
//  WelcomeNoticePage.swift
//  FlowDown
//

import SnapKit
import Storage
import UIKit

/// A page with a large title, a 44 pt symbol and a few paragraphs over the
/// action bar.
final class WelcomeNoticePage: UIViewController {
    struct Paragraph {
        enum Style {
            /// Body text in the primary label color.
            case body
            /// Footnote text in the secondary label color.
            case note
        }

        var text: String
        var style: Style
    }

    private let flow: WelcomeFlow
    private let symbolName: String
    private let symbolColor: UIColor
    private let paragraphs: [Paragraph]
    private let buttonTitle: String
    private let action: (WelcomeFlow) -> Void

    init(
        flow: WelcomeFlow,
        title: String,
        symbolName: String,
        symbolColor: UIColor,
        paragraphs: [Paragraph],
        buttonTitle: String,
        action: @escaping (WelcomeFlow) -> Void,
    ) {
        self.flow = flow
        self.symbolName = symbolName
        self.symbolColor = symbolColor
        self.paragraphs = paragraphs
        self.buttonTitle = buttonTitle
        self.action = action
        super.init(nibName: nil, bundle: nil)
        self.title = title
        navigationItem.largeTitleDisplayMode = .always
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WelcomeStyle.groupedBackground

        let symbol = UIImageView(image: UIImage(systemName: symbolName))
        symbol.tintColor = symbolColor
        symbol.preferredSymbolConfiguration = .init(pointSize: 44)
        symbol.isAccessibilityElement = false

        let stack = UIStackView(arrangedSubviews: [symbol])
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 16

        var previous: UILabel?
        for paragraph in paragraphs {
            let label = UILabel()
            label.text = paragraph.text
            label.numberOfLines = 0
            label.adjustsFontForContentSizeCategory = true
            switch paragraph.style {
            case .body:
                label.font = WelcomeStyle.subtitleFont
                label.textColor = WelcomeStyle.titleColor
            case .note:
                label.font = WelcomeStyle.detailFont
                label.textColor = WelcomeStyle.detailColor
                // The note stands apart from the text above it.
                if let previous {
                    stack.setCustomSpacing(24, after: previous)
                }
            }
            stack.addArrangedSubview(label)
            previous = label
        }

        let scrollView = UIScrollView()
        scrollView.alwaysBounceVertical = true
        let contentView = UIView()
        let actionBar = WelcomeActionBar(title: buttonTitle) { [weak self] in
            guard let self else { return }
            action(flow)
        }
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stack)
        view.addSubview(actionBar)

        scrollView.snp.makeConstraints { x in
            x.top.leading.trailing.equalToSuperview()
            x.bottom.equalTo(actionBar.snp.top)
        }
        contentView.snp.makeConstraints { x in
            x.edges.equalToSuperview()
            x.width.equalTo(scrollView.snp.width)
        }
        // under the large title, and in line with it
        stack.snp.makeConstraints { x in
            x.top.equalToSuperview().inset(8)
            x.bottom.equalToSuperview().inset(24)
            x.leading.trailing.equalTo(view.layoutMarginsGuide)
        }
        actionBar.snp.makeConstraints { x in
            x.leading.trailing.bottom.equalToSuperview()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
}

extension WelcomeNoticePage {
    /// Your Data: where chats live, and where iCloud Sync is turned on.
    static func data(flow: WelcomeFlow) -> WelcomeNoticePage {
        var paragraphs: [Paragraph] = [
            .init(
                text: String(localized: "Your chats and keys are stored on this device. We don't collect any of your data."),
                style: .body,
            ),
        ]
        if SyncEngine.isCloudSyncSupported {
            paragraphs.append(.init(
                text: String(localized: "To see your chats on your other devices, turn on iCloud Sync in Settings > Data."),
                style: .body,
            ))
        }
        return WelcomeNoticePage(
            flow: flow,
            title: String(localized: "Your Data"),
            symbolName: "icloud",
            symbolColor: WelcomeStyle.accent,
            paragraphs: paragraphs,
            buttonTitle: String(localized: "Next"),
        ) { flow in
            flow.showCaution()
        }
    }

    /// Before You Start: models can be wrong, and the app comes without
    /// warranty. Get Started finishes the welcome.
    static func caution(flow: WelcomeFlow) -> WelcomeNoticePage {
        WelcomeNoticePage(
            flow: flow,
            title: String(localized: "Before You Start"),
            symbolName: "exclamationmark.triangle.fill",
            symbolColor: WelcomeStyle.caution,
            paragraphs: [
                .init(
                    text: String(localized: "AI can make mistakes. Check important information before you rely on it."),
                    style: .body,
                ),
                .init(
                    text: String(localized: "FlowDown is open-source software, provided as is, without warranty of any kind."),
                    style: .note,
                ),
            ],
            buttonTitle: String(localized: "Get Started"),
        ) { flow in
            flow.finish()
        }
    }
}

// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeCautionController.swift,
// itself copied from Irisin). FlowDown's Before You Start page, without the
// symbol.
//
//  WelcomeNoticePage.swift
//  FlowDown
//

import CoreText
import SnapKit
import UIKit

/// A page with a large title and a few paragraphs over the action bar.
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
    private let paragraphs: [Paragraph]
    private let buttonTitle: String
    private let action: (WelcomeFlow) -> Void

    init(
        flow: WelcomeFlow,
        title: String,
        paragraphs: [Paragraph],
        buttonTitle: String,
        action: @escaping (WelcomeFlow) -> Void,
    ) {
        self.flow = flow
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

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .leading
        stack.spacing = 14

        var previous: (label: UILabel, style: Paragraph.Style)?
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
                // The notes are the license, English in every language. Say
                // so, or in German the label is sized a line short of the
                // text and cuts its end.
                label.attributedText = NSAttributedString(string: paragraph.text, attributes: [
                    .font: WelcomeStyle.detailFont,
                    .foregroundColor: WelcomeStyle.detailColor,
                    NSAttributedString.Key(kCTLanguageAttributeName as String): "en",
                ])
                label.accessibilityLanguage = "en"
                // The notes stand apart from the text above them.
                if let previous, previous.style == .body {
                    stack.setCustomSpacing(24, after: previous.label)
                }
            }
            stack.addArrangedSubview(label)
            previous = (label, paragraph.style)
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
            x.top.equalToSuperview().inset(16)
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
    /// Sections 15 and 16 of LICENSE, word for word and never translated: a
    /// legal text says what it says in its own words. The file's line breaks
    /// are removed.
    static let disclaimer = [
        "15. Disclaimer of Warranty.",
        "THERE IS NO WARRANTY FOR THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW.  EXCEPT WHEN OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES PROVIDE THE PROGRAM \"AS IS\" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.  THE ENTIRE RISK AS TO THE QUALITY AND PERFORMANCE OF THE PROGRAM IS WITH YOU.  SHOULD THE PROGRAM PROVE DEFECTIVE, YOU ASSUME THE COST OF ALL NECESSARY SERVICING, REPAIR OR CORRECTION.",
        "16. Limitation of Liability.",
        "IN NO EVENT UNLESS REQUIRED BY APPLICABLE LAW OR AGREED TO IN WRITING WILL ANY COPYRIGHT HOLDER, OR ANY OTHER PARTY WHO MODIFIES AND/OR CONVEYS THE PROGRAM AS PERMITTED ABOVE, BE LIABLE TO YOU FOR DAMAGES, INCLUDING ANY GENERAL, SPECIAL, INCIDENTAL OR CONSEQUENTIAL DAMAGES ARISING OUT OF THE USE OR INABILITY TO USE THE PROGRAM (INCLUDING BUT NOT LIMITED TO LOSS OF DATA OR DATA BEING RENDERED INACCURATE OR LOSSES SUSTAINED BY YOU OR THIRD PARTIES OR A FAILURE OF THE PROGRAM TO OPERATE WITH ANY OTHER PROGRAMS), EVEN IF SUCH HOLDER OR OTHER PARTY HAS BEEN ADVISED OF THE POSSIBILITY OF SUCH DAMAGES.",
    ]

    /// Before You Start: models can be wrong, and the license's disclaimer.
    /// Get Started finishes the welcome.
    static func caution(flow: WelcomeFlow) -> WelcomeNoticePage {
        WelcomeNoticePage(
            flow: flow,
            title: String(localized: "Before You Start"),
            paragraphs: [
                .init(
                    text: String(localized: "AI can make mistakes. Check important information before you rely on it."),
                    style: .body,
                ),
            ] + disclaimer.map { .init(text: $0, style: .note) },
            buttonTitle: String(localized: "Get Started"),
        ) { flow in
            flow.finish()
        }
    }
}

//
//  EvaluationCaseDetailController.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import SnapKit
import UIKit

final class EvaluationCaseDetailController: StackScrollController {
    private let caseItem: EvaluationManifest.Suite.Case
    private let session: EvaluationSession

    init(caseItem: EvaluationManifest.Suite.Case, session: EvaluationSession) {
        self.caseItem = caseItem
        self.session = session
        super.init(nibName: nil, bundle: nil)
        title = caseItem.title
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = caseItem.title
        setupNavigation()
    }

    override func setupContentViews() {
        buildContentSection(
            header: String(localized: "Input Content"),
            contents: caseItem.content,
        )

        if let output = caseItem.results.last?.output {
            buildContentSection(
                header: String(localized: "Model Output"),
                contents: output,
            )
        } else {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionHeaderView().with(header: String(localized: "Model Output")),
            ) { $0.bottom /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: String(localized: "No output available.")),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
        }

        buildVerifiersSection()
        buildJudgementSectionIfNeeded()
        buildConclusionSection()
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    private func buildConclusionSection() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Conclusion")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let outcome = caseItem.results.last?.outcome ?? .notDetermined

        let iconName: String
        let statusText: String.LocalizationValue
        switch outcome {
        case .pass:
            iconName = "checkmark.seal.fill"
            statusText = "Passed"
        case .fail:
            iconName = "xmark.seal.fill"
            statusText = "Failed"
        case .processing:
            iconName = "gearshape.fill"
            statusText = "Running"
        case .awaitingJudging:
            iconName = "eye.fill"
            statusText = "Judging"
        case .notDetermined:
            iconName = "circle.dotted"
            statusText = "Pending"
        }

        let view = EvaluationCaseDetailTextCardView(
            headerText: String(localized: "Conclusion"),
            headerIconSystemName: iconName,
            bodyText: String(localized: statusText),
        )
        stackView.addArrangedSubviewWithMargin(view) { insets in
            insets.top = 12
            insets.bottom = 12
            insets.left = 16
            insets.right = 16
        }
        stackView.addArrangedSubview(SeparatorView())
    }

    private func setupNavigation() {
        let menu = EvaluationMenuFactory.makeMenu(
            session: session,
            caseItem: caseItem,
            onUpdate: { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            },
        )

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: menu,
        )
        navigationItem.rightBarButtonItem?.accessibilityLabel = String(localized: "Actions")
    }

    private func judge(_ outcome: EvaluationManifest.Suite.Case.Result.Outcome) {
        guard let result = caseItem.results.last else { return }
        result.outcome = outcome
        _ = try? EvaluationSessionManager.shared.save(session)
        NotificationCenter.default.post(name: .evaluationSessionDidUpdate, object: session)
        navigationController?.popViewController(animated: true)
    }

    private func buildContentSection(
        header: String,
        contents: [EvaluationManifest.Suite.Case.Content],
    ) {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: header),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if contents.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: String(localized: "No content.")),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            return
        }

        for (idx, content) in contents.enumerated() {
            let block = makeContentBlockView(content)
            stackView.addArrangedSubviewWithMargin(block) { insets in
                insets.top = 12
                insets.bottom = 12
                insets.left = 16
                insets.right = 16
            }
            if idx < contents.count - 1 { stackView.addArrangedSubview(SeparatorView()) }
        }

        stackView.addArrangedSubview(SeparatorView())
    }

    private func buildVerifiersSection() {
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Verifiers")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        if caseItem.verifier.isEmpty {
            stackView.addArrangedSubviewWithMargin(
                ConfigurableSectionFooterView().with(footer: String(localized: "No verifier configured.")),
            ) { $0.top /= 2 }
            stackView.addArrangedSubview(SeparatorView())
            return
        }

        for (idx, verifier) in caseItem.verifier.enumerated() {
            let text = verifierDescription(verifier)
            let view = EvaluationCaseDetailTextCardView(
                headerText: String(localized: "Verifier"),
                headerIconSystemName: "checkmark.seal",
                bodyText: text,
            )
            stackView.addArrangedSubviewWithMargin(view) { insets in
                insets.top = 12
                insets.bottom = 12
                insets.left = 16
                insets.right = 16
            }
            if idx < caseItem.verifier.count - 1 { stackView.addArrangedSubview(SeparatorView()) }
        }
        stackView.addArrangedSubview(SeparatorView())
    }

    private func buildJudgementSectionIfNeeded() {
        guard let result = caseItem.results.last, result.outcome == .awaitingJudging else { return }

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView().with(header: String(localized: "Judgement")),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let buttons = EvaluationCaseDetailButtonRowView(
            primaryTitle: String(localized: "Pass"),
            primaryColor: .systemGreen,
            secondaryTitle: String(localized: "Fail"),
            secondaryColor: .systemRed,
            onPrimary: { [weak self] in self?.judge(.pass) },
            onSecondary: { [weak self] in self?.judge(.fail) },
        )

        stackView.addArrangedSubviewWithMargin(buttons) { insets in
            insets.top = 12
            insets.bottom = 12
            insets.left = 16
            insets.right = 16
        }
        stackView.addArrangedSubview(SeparatorView())
        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView().with(footer: String(localized: "You can also use the Actions menu to re-run or delete.")),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())
    }

    private func makeContentBlockView(_ content: EvaluationManifest.Suite.Case.Content) -> UIView {
        let typeText: String.LocalizationValue
        let bodyText: String
        let secondaryText: String
        let typeIcon: String?

        let parametersTitle = String(localized: "Parameters")

        switch content.type {
        case .instruct:
            typeText = "System Instruction"
            typeIcon = "gearshape.2"
            bodyText = content.textRepresentation ?? ""
            secondaryText = ""
        case .request:
            typeText = "User Request"
            typeIcon = "person.fill.viewframe"
            bodyText = content.textRepresentation ?? ""
            secondaryText = ""
        case .reply:
            typeText = "Assistant Reply"
            typeIcon = "sparkles"
            bodyText = content.textRepresentation ?? ""
            secondaryText = ""
        case .reasoning:
            typeText = "Reasoning"
            typeIcon = "brain.head.profile"
            bodyText = content.textRepresentation ?? ""
            secondaryText = ""
        case .toolDefinition:
            typeText = "Tool Definition"
            typeIcon = "hammer.fill"
            bodyText = content.toolRepresentation?.name ?? String(localized: "Unknown")
            var secondaryParts: [String] = []
            let descriptionText = content.toolRepresentation?.description ?? ""
            if !descriptionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                secondaryParts.append(descriptionText)
            }
            if let params = content.toolRepresentation?.parameters {
                if let pretty = prettyPrintedJSON(from: params) {
                    secondaryParts.append([parametersTitle, pretty].joined(separator: "\n\n"))
                } else if !params.isEmpty {
                    secondaryParts.append([parametersTitle, String(describing: params)].joined(separator: "\n\n"))
                }
            }
            secondaryText = secondaryParts.joined(separator: "\n\n")
        case .toolRequest:
            typeText = "Tool Call"
            typeIcon = "phone.arrow.up.right"
            if let toolName = content.toolRepresentation?.name {
                let key: String.LocalizationValue = "Calling: \(toolName)"
                bodyText = String(localized: key)
            } else {
                bodyText = String(localized: "Calling Tool...")
            }
            var secondaryParts: [String] = []
            if let params = content.toolRepresentation?.parameters {
                if let pretty = prettyPrintedJSON(from: params) {
                    secondaryParts.append([parametersTitle, pretty].joined(separator: "\n\n"))
                } else if !params.isEmpty {
                    secondaryParts.append([parametersTitle, String(describing: params)].joined(separator: "\n\n"))
                }
            } else if let rawArgs = content.textRepresentation, !rawArgs.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let argsText = prettyPrintedJSON(from: rawArgs) ?? rawArgs
                secondaryParts.append([parametersTitle, argsText].joined(separator: "\n\n"))
            }
            secondaryText = secondaryParts.joined(separator: "\n\n")
        case .toolResponse:
            typeText = "Tool Output"
            typeIcon = "phone.arrow.down.left"
            bodyText = content.textRepresentation ?? ""
            var secondaryParts: [String] = []
            if let params = content.toolRepresentation?.parameters {
                if let pretty = prettyPrintedJSON(from: params) {
                    secondaryParts.append([parametersTitle, pretty].joined(separator: "\n\n"))
                } else if !params.isEmpty {
                    secondaryParts.append([parametersTitle, String(describing: params)].joined(separator: "\n\n"))
                }
            }
            secondaryText = secondaryParts.joined(separator: "\n\n")
        }

        var headerText = String(localized: typeText)
        if headerText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            headerText = String(localized: "Content")
        }

        var combined = bodyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !secondaryText.isEmpty {
            combined = [combined, secondaryText].joined(separator: "\n\n")
        }

        return EvaluationCaseDetailTextCardView(
            headerText: headerText,
            headerIconSystemName: typeIcon,
            bodyText: combined,
        )
    }

    private func verifierDescription(_ verifier: EvaluationManifest.Suite.Case.Verifier) -> String {
        switch verifier {
        case .open:
            String(localized: "Open (Human Eval)")
        case let .match(pattern):
            String(localized: "Match: '\(pattern)'" as String.LocalizationValue)
        case let .matchCaseInsensitive(pattern):
            String(localized: "Match (Case Insensitive): '\(pattern)'" as String.LocalizationValue)
        case let .contains(pattern):
            String(localized: "Contains: '\(pattern)'" as String.LocalizationValue)
        case let .containsCaseInsensitive(pattern):
            String(localized: "Contains (Case Insensitive): '\(pattern)'" as String.LocalizationValue)
        case let .matchRegularExpression(pattern):
            String(localized: "Regex: '\(pattern)'" as String.LocalizationValue)
        case let .toolCalled(name):
            String(localized: "Tool Call") + ": \(name)"
        case let .tool(param, value):
            String(localized: "Tool Param: \(param) == \(String(describing: value))")
        }
    }

    private func prettyPrintedJSON(from jsonString: String) -> String? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            return nil
        }
        guard let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) else {
            return nil
        }
        return String(decoding: pretty, as: UTF8.self)
    }

    private func prettyPrintedJSON(from parameters: [String: AnyCodingValue]) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(parameters) else {
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }
}

private final class EvaluationCaseDetailTextCardView: UIView {
    private let headerLabel = UILabel()
    private let textView = UITextView()

    init(
        headerText: String,
        headerIconSystemName: String?,
        bodyText: String,
    ) {
        super.init(frame: .zero)
        backgroundColor = .gray.withAlphaComponent(0.1)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true

        headerLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        headerLabel.textColor = .secondaryLabel
        headerLabel.numberOfLines = 1

        if let name = headerIconSystemName, let icon = UIImage(systemName: name) {
            let attachment = NSTextAttachment()
            attachment.image = icon.withTintColor(.secondaryLabel)
            attachment.bounds = CGRect(x: 0, y: -2, width: 14, height: 14)
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: UIColor.secondaryLabel,
            ]
            let attributed = NSMutableAttributedString(attachment: attachment)
            attributed.append(NSAttributedString(string: "  \(headerText)", attributes: attrs))
            headerLabel.attributedText = attributed
        } else {
            headerLabel.text = headerText
        }

        textView.backgroundColor = .clear
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.textContainerInset = .init(top: 0, left: 0, bottom: 0, right: 0)
        textView.textContainer.lineFragmentPadding = 0
        textView.font = .monospacedSystemFont(ofSize: 14, weight: .regular)
        textView.textColor = .label
        textView.text = bodyText

        addSubview(headerLabel)
        addSubview(textView)

        headerLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(12)
            make.horizontalEdges.equalToSuperview().inset(16)
        }

        textView.snp.makeConstraints { make in
            make.top.equalTo(headerLabel.snp.bottom).offset(8)
            make.horizontalEdges.equalToSuperview().inset(16)
            make.bottom.equalToSuperview().offset(-16)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private final class EvaluationCaseDetailButtonRowView: UIView {
    private let stackView = UIStackView()

    init(
        primaryTitle: String,
        primaryColor: UIColor,
        secondaryTitle: String,
        secondaryColor: UIColor,
        onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void,
    ) {
        super.init(frame: .zero)

        backgroundColor = .gray.withAlphaComponent(0.1)
        layer.cornerRadius = 10
        layer.cornerCurve = .continuous
        clipsToBounds = true

        stackView.axis = .horizontal
        stackView.spacing = 16
        stackView.distribution = .fillEqually

        let primary = UIButton(configuration: .filled())
        primary.configuration?.title = primaryTitle
        primary.configuration?.baseBackgroundColor = primaryColor
        primary.addAction(UIAction { _ in onPrimary() }, for: .touchUpInside)

        let secondary = UIButton(configuration: .filled())
        secondary.configuration?.title = secondaryTitle
        secondary.configuration?.baseBackgroundColor = secondaryColor
        secondary.addAction(UIAction { _ in onSecondary() }, for: .touchUpInside)

        addSubview(stackView)
        stackView.addArrangedSubview(secondary)
        stackView.addArrangedSubview(primary)

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
            make.height.equalTo(50)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

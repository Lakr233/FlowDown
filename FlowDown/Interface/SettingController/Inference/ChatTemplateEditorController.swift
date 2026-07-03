//
//  ChatTemplateEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/28/25.
//

import AlertController
import Combine
import ConfigurableKit
import UIKit

class ChatTemplateEditorController: StackScrollController, UITextViewDelegate {
    let templateIdentifier: ChatTemplate.ID
    private var template: ChatTemplate

    init(templateIdentifier: ChatTemplate.ID) {
        self.templateIdentifier = templateIdentifier
        guard let template = ChatTemplateManager.shared.template(for: templateIdentifier) else {
            fatalError("template not found")
        }
        self.template = template
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Edit Template")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    var cancellables: Set<AnyCancellable> = .init()

    lazy var nameView = ConfigurableInfoView().setTapBlock { view in
        let input = AlertInputViewController(
            title: "Edit Name",
            message: "The display name of this chat template.",
            placeholder: "Enter template name",
            text: self.template.name,
        ) { output in
            self.template = self.template.with { $0.name = output }
            self.title = self.template.name
            view.configure(value: output)
        }
        view.parentViewController?.present(input, animated: true)
    }

    lazy var textEditor = UITextView().with {
        $0.isSelectable = true
        $0.isEditable = true
        $0.isScrollEnabled = true
        $0.textContainerInset = .init(inset: 12)
        $0.font = .preferredFont(forTextStyle: .body)
        $0.backgroundColor = .secondarySystemBackground
        $0.layer.cornerRadius = 8
        $0.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        $0.contentInset = .zero
        $0.snp.makeConstraints { make in
            make.height.equalTo(200)
        }
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background

        navigationItem.rightBarButtonItem = .init(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped),
        )

        navigationItem.leftBarButtonItem = .init(
            image: UIImage(systemName: "sparkles"),
            style: .plain,
            target: self,
            action: #selector(sparklesTapped),
        )

        ChatTemplateManager.shared.$templates
            .removeDuplicates()
            .ensureMainThread()
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] templates in
                guard let self, isVisible else { return }
                guard templates[templateIdentifier] != nil else {
                    navigationController?.popViewController(animated: true)
                    return
                }
            }
            .store(in: &cancellables)
    }

    @objc func checkTapped() {
        ChatTemplateManager.shared.update(template)
        navigationController?.popViewController(animated: true)
    }

    @objc func sparklesTapped() {
        let defaultModel = ModelManager.ModelIdentifier.defaultModelForConversation

        guard !defaultModel.isEmpty else {
            let alert = AlertViewController(
                title: "No Model Selected",
                message: "Please select a default chat model in settings before using rewrite features.",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK") {
                    context.dispose()
                }
            }
            present(alert, animated: true)
            return
        }

        let modelName = ModelManager.shared.modelName(identifier: defaultModel)

        let input = AlertInputViewController(
            title: "Rewrite",
            message: "You can use \(modelName) to rewrite this template, e.g., 'Add more instructions to the template.', or 'Make it more concise.'...",
            placeholder: "Enter instructions...",
            text: "",
        ) { [self] instructions in
            guard !instructions.isEmpty else { return }
            Indicator.progress(
                title: "Rewriting Template",
                controller: self,
            ) { completionHandler in
                let result = await withCheckedContinuation { continuation in
                    ChatTemplateManager.shared.rewriteTemplate(
                        template: self.template,
                        request: instructions,
                        model: defaultModel,
                    ) { result in
                        continuation.resume(returning: result)
                    }
                }
                let newTemplate = try result.get()
                await completionHandler {
                    self.template = newTemplate
                    self.title = newTemplate.name
                    self.nameView.configure(value: newTemplate.name)
                    self.textEditor.text = newTemplate.prompt
                }
            }
        }
        present(input, animated: true)
    }

    @objc func deleteTapped() {
        presentDeleteConfirmation(
            title: "Delete Template",
            message: "Are you sure you want to delete this template? This action cannot be undone.",
        ) { [weak self] in
            guard let self else { return }
            ChatTemplateManager.shared.remove(for: templateIdentifier)
        }
    }

    override func setupContentViews() {
        super.setupContentViews()

        // MARK: - AVATAR

        let avatarContainer = UIView()
        avatarContainer.snp.makeConstraints { make in
            make.height.equalTo(64)
        }
        stackView.addArrangedSubviewWithMargin(avatarContainer)
        stackView.addArrangedSubview(SeparatorView())

        let avatarView = UIImageView()
        avatarView.layer.cornerRadius = 4
        avatarView.contentMode = .scaleAspectFill
        avatarView.image = UIImage(data: template.avatar) ?? .init()
        avatarContainer.addSubview(avatarView)
        avatarView.isUserInteractionEnabled = true
        avatarView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(pickAvatarTapped(_:))))

        avatarView.snp.makeConstraints { make in
            make.width.height.equalTo(64)
            make.center.equalToSuperview()
        }

        // MARK: - NAME

        nameView.configure(icon: .init(systemName: "rosette"))
        nameView.configure(title: "Name")
        nameView.configure(description: "The display name of this chat template.")
        nameView.configure(value: template.name)
        stackView.addArrangedSubviewWithMargin(nameView)
        stackView.addArrangedSubview(SeparatorView())

        // MARK: PROMPT

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Prompt"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        textEditor.text = template.prompt
        textEditor.delegate = self
        stackView.addArrangedSubviewWithMargin(textEditor) {
            $0.left -= 8
            $0.right -= 8
            $0.top -= 8
            $0.bottom -= 8
        }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionFooterView()
                .with(footer: "The prompt serves as the initial instruction for the language model. It defines the character, behavior, and context for the conversation."),
        ) { $0.top /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Configuration"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let promptBehaviorView = ConfigurableInfoView()
        promptBehaviorView.configure(icon: .init(systemName: "gear"))
        promptBehaviorView.configure(title: "Application Prompt Behavior")
        promptBehaviorView.configure(description: "Regarding whether the prompt from the application should be inherited or ignored when creating a new conversation from this template.")
        let behaviorTitle = template.inheritApplicationPrompt ? String(localized: "Inherit") : String(localized: "Ignore")
        promptBehaviorView.configure(value: behaviorTitle)
        promptBehaviorView.use {
            [
                UIAction(
                    title: String(localized: "Inherit"),
                    image: UIImage(systemName: "arrow.down.circle"),
                ) { _ in
                    self.template = self.template.with { $0.inheritApplicationPrompt = true }
                    promptBehaviorView.configure(value: String(localized: "Inherit"))
                },
                UIAction(
                    title: String(localized: "Ignore"),
                    image: UIImage(systemName: "xmark.circle"),
                ) { _ in
                    self.template = self.template.with { $0.inheritApplicationPrompt = false }
                    promptBehaviorView.configure(value: String(localized: "Ignore"))
                },
            ]
        }
        stackView.addArrangedSubviewWithMargin(promptBehaviorView)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(
            ConfigurableSectionHeaderView()
                .with(header: "Management"),
        ) { $0.bottom /= 2 }
        stackView.addArrangedSubview(SeparatorView())

        let copyAction = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            var newTemplate = template
            newTemplate.id = UUID()
            newTemplate.name = template.name + " " + String(localized: "Copy")
            ChatTemplateManager.shared.addTemplate(newTemplate)
            let editor = ChatTemplateEditorController(templateIdentifier: newTemplate.id)
            navigationController?.pushViewController(editor, animated: true)
        }
        copyAction.configure(icon: UIImage(systemName: "doc.on.doc"))
        copyAction.configure(title: "Create Copy")
        copyAction.configure(description: "Create a duplicate of this template for further editing.")
        stackView.addArrangedSubviewWithMargin(copyAction)
        stackView.addArrangedSubview(SeparatorView())

        let exportOption = ConfigurableActionView { @MainActor [weak self] controller in
            guard let self else { return }
            guard let data = try? ChatTemplateManager.shared.exportTemplateData(template) else { return }
            let fileName = "Export-\(template.name.sanitizedFileName)"
            DisposableExporter(
                data: data,
                name: fileName,
                pathExtension: "fdtemplate",
                title: "Export Template",
            ).run(anchor: controller.view)
        }
        exportOption.configure(icon: UIImage(systemName: "square.and.arrow.up"))
        exportOption.configure(title: "Export Template")
        exportOption.configure(description: "Export this chat template as a .fdtemplate file for sharing or backup.")
        stackView.addArrangedSubviewWithMargin(exportOption)
        stackView.addArrangedSubview(SeparatorView())

        let deleteAction = ConfigurableActionView { @MainActor [weak self] _ in
            guard let self else { return }
            deleteTapped()
        }
        deleteAction.configure(icon: UIImage(systemName: "trash"))
        deleteAction.configure(title: "Delete Template")
        deleteAction.configure(description: "Delete this template permanently.")
        deleteAction.titleLabel.textColor = .systemRed
        deleteAction.iconView.tintColor = .systemRed
        deleteAction.descriptionLabel.textColor = .systemRed
        deleteAction.imageView.tintColor = .systemRed
        stackView.addArrangedSubviewWithMargin(deleteAction)
        stackView.addArrangedSubview(SeparatorView())

        stackView.addArrangedSubviewWithMargin(UIView())

        let icon = UIImageView().with {
            $0.image = UIImage(systemName: "text.bubble")
            $0.tintColor = .label.withAlphaComponent(0.25)
            $0.contentMode = .scaleAspectFit
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(24)
            }
        }
        stackView.addArrangedSubviewWithMargin(icon) { $0.bottom /= 2 }

        let footer = UILabel().with {
            $0.font = .rounded(
                ofSize: UIFont.preferredFont(forTextStyle: .footnote).pointSize,
                weight: .regular,
            )
            $0.textColor = .label.withAlphaComponent(0.25)
            $0.numberOfLines = 0
            $0.text = templateIdentifier.uuidString
            $0.textAlignment = .center
        }
        stackView.addArrangedSubviewWithMargin(footer) { $0.top /= 2 }
        stackView.addArrangedSubviewWithMargin(UIView())
    }

    func textViewDidChange(_ textView: UITextView) {
        template = template.with { $0.prompt = textView.text }
    }

    @objc func pickAvatarTapped(_ sender: Any?) {
        let gesture = sender as? UITapGestureRecognizer
        guard let view = gesture?.view as? UIImageView else {
            assertionFailure()
            return
        }
        let picker = EmojiPickerViewController(sourceView: view) { emoji in
            let data = emoji.emoji.textToImage(size: 64)?.pngData()
            self.template = self.template.with { $0.avatar = data ?? .init() }
            view.image = UIImage(data: data ?? .init()) ?? .init()
        }
        view.parentViewController?.present(picker, animated: true)
    }
}

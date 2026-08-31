//
//  CodeEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/24/25.
//

import RunestoneEditor
import UIKit

class CodeEditorController: UIViewController {
    let textView = RunestoneEditorView.new()

    lazy var doneBarButtonItem: UIBarButtonItem = .init(
        barButtonSystemItem: .done,
        target: self,
        action: #selector(done),
    )
    lazy var cancelBarButtonItem: UIBarButtonItem = .init(
        barButtonSystemItem: .cancel,
        target: self,
        action: #selector(dispose),
    )

    init(language: String? = nil, text: String) {
        super.init(nibName: nil, bundle: nil)

        textView.clipsToBounds = true
        textView.alwaysBounceVertical = true
        textView.isEditable = true
        textView.text = text
        textView.apply(theme: TomorrowTheme())

        navigationItem.rightBarButtonItems = [doneBarButtonItem]

        if let language,
           let languageObject = TreeSitterLanguage.language(withIdentifier: language)
        {
            textView.applyAsync(language: languageObject, text: text) {}
        } else if let languageObject = TreeSitterLanguage.language(withIdentifier: "markdown") {
            textView.applyAsync(language: languageObject, text: text) {}
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    private var collector: ((String) -> Void)?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .background

        view.addSubview(textView)
        textView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        textView.textContainerInset.bottom = 400
    }

    @objc func done() {
        if let collector { collector(textView.text) }
        dispose()
    }

    @objc func dispose() {
        if navigationController?.viewControllers.count == 1 {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }

    func collectEditedContent(_ block: @escaping (String) -> Void) {
        assert(collector == nil)
        assert(textView.isEditable)
        collector = block
        navigationItem.leftBarButtonItems = [cancelBarButtonItem]
    }
}

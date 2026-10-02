//
//  SimpleSpeechController.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/18/25.
//

import AlertController
import Speech
import UIKit

class SimpleSpeechController: AlertBaseController {
    var callback: (String) -> Void = { _ in }
    var onErrorCallback: (Error) -> Void = { _ in }

    let divider = UIView()
    let doneButton = UIButton()
    let textView = UITextView()
    let placeholderText = "..."

    var sessionItems: [Any] = []

    override init() {
        super.init()
        overrideUserInterfaceStyle = .dark
    }

    override func contentViewDidLoad() {
        super.contentViewDidLoad()
        NSLayoutConstraint.activate([
            contentView.widthAnchor.constraint(equalToConstant: 300),
            contentView.heightAnchor.constraint(equalToConstant: 200),
        ])

        divider.backgroundColor = .white.withAlphaComponent(0.1)
        contentView.addSubview(divider)
        doneButton.isEnabled = false
        doneButton.setTitle(NSLocalizedString("Preparing Transcript...", comment: ""), for: .normal)
        doneButton.setTitleColor(.white, for: .normal)
        doneButton.setTitleColor(.white.withAlphaComponent(0.25), for: .disabled)
        doneButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        doneButton.addTarget(self, action: #selector(stopTranscriptButton), for: .touchUpInside)
        contentView.addSubview(doneButton)

        textView.isEditable = false
        textView.isScrollEnabled = true
        textView.isSelectable = false
        textView.text = placeholderText
        textView.textColor = .label
        textView.font = .systemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .title3).pointSize,
            weight: .semibold,
        )
        textView.backgroundColor = .clear
        textView.contentInset = .zero
        textView.textContainerInset = .zero
        textView.showsVerticalScrollIndicator = false
        textView.showsHorizontalScrollIndicator = false
        contentView.addSubview(textView)
    }

    override func dimmingViewTapped() {
        super.dimmingViewTapped()
        stopTranscriptButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task { @MainActor in await startTranscript() }
    }

    override func contentViewLayout(in bounds: CGRect) {
        super.contentViewLayout(in: bounds)

        doneButton.frame = .init(
            x: 0,
            y: bounds.height - 50,
            width: bounds.width,
            height: 50,
        )
        divider.frame = .init(
            x: 0,
            y: bounds.height - 50,
            width: bounds.width,
            height: 1,
        )
        textView.frame = .init(
            x: 10,
            y: 10,
            width: bounds.width - 20,
            height: divider.frame.minY - 20,
        )
    }
}

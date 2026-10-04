//
//  JsonEditorController.swift
//  FlowDown
//
//  Created by Willow Zhang on 10/31/25.
//

import AlertController
import RunestoneEditor
import Storage
import UIKit

class JsonEditorController: CodeEditorController {
    /// Reports the draft on every edit. When the editor closes without Done,
    /// reports the original text again so callers drop the discarded draft.
    var onTextDidChange: ((String) -> Void)?

    private let initialText: String
    private var didCommitEdit = false

    var secondaryMenuBuilder: ((JsonEditorController) -> (UIMenu))? {
        didSet {
            if let secondaryMenuBuilder {
                navigationItem.rightBarButtonItems = [
                    doneBarButtonItem,
                    .init(systemItem: .add, menu: secondaryMenuBuilder(self)),
                ]
            } else {
                navigationItem.rightBarButtonItems = [doneBarButtonItem]
            }
        }
    }

    var currentDictionary: [String: Any] {
        let text = textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data),
              let dict = object as? [String: Any]
        else {
            return .init()
        }
        return dict
    }

    init(text: String) {
        initialText = text
        super.init(language: "json", text: text)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        textView.editorDelegate = self
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let isClosing = isMovingFromParent
            || isBeingDismissed
            || navigationController?.isBeingDismissed == true
        guard isClosing, !didCommitEdit else { return }
        onTextDidChange?(initialText)
    }

    func set(dic: [String: Any]) {
        do {
            let data = try JSONSerialization.data(withJSONObject: dic, options: [.prettyPrinted, .sortedKeys])
            guard let text = String(data: data, encoding: .utf8) else {
                throw NSError()
            }
            textView.text = text
            onTextDidChange?(textView.text)
        } catch {
            presentErrorAlert(message: error.localizedDescription)
        }
    }

    override func done() {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = "{}"
            onTextDidChange?(textView.text)
            didCommitEdit = true
            super.done()
            return
        }
        guard let data = textView.text.data(using: .utf8) else {
            presentErrorAlert(message: "Unable to decode text into data.")
            return
        }
        do {
            let object = try JSONSerialization.jsonObject(with: data)
            guard object is [String: Any] else {
                throw NSError(
                    domain: "JSONValidation",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "JSON must be an object (dictionary), not an array or primitive.")],
                )
            }
            Logger.ui.infoFile("JsonEditorController done with valid JSON object")
        } catch {
            presentErrorAlert(message: String(localized: "Unable to parse JSON: \(error.localizedDescription)"))
            return
        }
        didCommitEdit = true
        super.done()
    }

    private func presentErrorAlert(message: String) {
        let alert = AlertViewController(
            title: "Error",
            message: .init(message),
        ) { context in
            context.allowSimpleDispose()
            context.addAction(title: "OK", attribute: .accent) {
                context.dispose()
            }
        }
        present(alert, animated: true)
    }

    func updateValue(_ callback: (_ temporaryDictionary: inout [String: Any]) -> Void) {
        let dict: [String: Any]
        do {
            dict = try Self.applying(callback, to: textView.text)
        } catch {
            presentErrorAlert(message: String(localized: "Unable to parse JSON: \(error.localizedDescription)"))
            return
        }
        set(dic: dict)
    }

    /// Applies `callback` to the object parsed from `text`. Throws instead of
    /// starting from an empty object so a preset never replaces unparseable text.
    static func applying(
        _ callback: (_ temporaryDictionary: inout [String: Any]) -> Void,
        to text: String,
    ) throws -> [String: Any] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var dict: [String: Any] = [:]
        if !trimmed.isEmpty {
            let object = try JSONSerialization.jsonObject(with: Data(trimmed.utf8))
            guard let object = object as? [String: Any] else {
                throw NSError(
                    domain: "JSONValidation",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: String(localized: "JSON must be an object (dictionary), not an array or primitive.")],
                )
            }
            dict = object
        }
        callback(&dict)
        return dict
    }
}

extension JsonEditorController: TextViewDelegate {
    func textViewDidChange(_ textView: TextView) {
        onTextDidChange?(textView.text)
    }
}

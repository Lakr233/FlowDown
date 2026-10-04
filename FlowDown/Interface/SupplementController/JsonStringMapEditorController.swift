//
//  JsonStringMapEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 6/30/25.
//

import AlertController
import UIKit

class JsonStringMapEditorController: CodeEditorController {
    init(text: String) {
        super.init(language: "json", text: text)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func done() {
        if textView.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            textView.text = "{}"
            super.done()
            return
        }
        let requiredDecodableType = [String: String].self
        guard let data = textView.text.data(using: .utf8) else {
            let alert = AlertViewController(
                title: "Error",
                message: "Unable to decode text into data.",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK", attribute: .accent) {
                    context.dispose()
                }
            }
            present(alert, animated: true)
            return
        }
        do {
            let object = try JSONDecoder().decode(requiredDecodableType, from: data)
            Logger.ui.infoFile("JsonStringMapEditorController done with object: \(object)")
        } catch {
            let alert = AlertViewController(
                title: "Error",
                message: "Unable to decode string key value map from text: \(error.localizedDescription)",
            ) { context in
                context.allowSimpleDispose()
                context.addAction(title: "OK", attribute: .accent) {
                    context.dispose()
                }
            }
            present(alert, animated: true)
            return
        }
        super.done()
    }
}

//
//  TextEditorController.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/18/25.
//

import AlertController
import UIKit

#if targetEnvironment(macCatalyst)
    typealias ContentHolderController = AlertBaseController
#else
    typealias ContentHolderController = FadeBarNavigationController
#endif

class TextEditorController: ContentHolderController {
    let rootController = TextEditorContentController()

    var text: String {
        get { rootController.text }
        set { rootController.text = newValue }
    }

    var callback: (String) -> Void {
        get { rootController.callback }
        set { rootController.callback = newValue }
    }

    #if targetEnvironment(macCatalyst)
        override init() {
            super.init(
                rootViewController: UINavigationController(rootViewController: rootController),
                preferredWidth: 555,
                preferredHeight: 555,
            )
        }
    #else
        init() {
            super.init(rootViewController: rootController)
            modalTransitionStyle = .coverVertical
            modalPresentationStyle = .formSheet
            preferredContentSize = .init(width: 555, height: 555 - navigationBar.frame.height)
            isModalInPresentation = true
        }
    #endif

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    #if !targetEnvironment(macCatalyst)
        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .white
        }
    #endif
}

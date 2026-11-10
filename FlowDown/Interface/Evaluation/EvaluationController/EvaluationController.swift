//
//  EvaluationController.swift
//  FlowDown
//
//  Created by qaq on 18/12/2025.
//

import UIKit

class EvaluationController: FadeBarNavigationController {
    init(identifier: ModelManager.ModelIdentifier) {
        super.init(rootViewController: EvaluationContentController(identifier: identifier))
        modalTransitionStyle = .coverVertical
        modalPresentationStyle = .formSheet
        preferredContentSize = .init(
            width: 600,
            height: 600,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
    }

    static func begin(controller: UIViewController?, model: ModelManager.ModelIdentifier?) {
        guard let controller else { return }
        guard let model else { return }
        let nav = EvaluationController(identifier: model)
        controller.present(nav, animated: true)
    }
}

private class EvaluationContentController: UIViewController {
    let identifier: ModelManager.ModelIdentifier
    init(identifier: ModelManager.ModelIdentifier) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let indicator = UIActivityIndicatorView()
        view.addSubview(indicator)
        indicator.startAnimating()
        indicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    var isAlreadyPresented: Bool = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        guard let nav = navigationController else {
            dismiss(animated: true)
            assertionFailure()
            return
        }
        if nav.viewControllers.count <= 1 {
            if isAlreadyPresented {
                dismiss(animated: true)
            } else {
                let assistant = EvaluationAssistantController(identifier: identifier)
                nav.pushViewController(assistant, animated: true)
                isAlreadyPresented = true
            }
        } else {
            assertionFailure()
            return
        }
    }
}

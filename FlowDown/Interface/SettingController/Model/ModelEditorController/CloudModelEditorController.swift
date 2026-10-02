//
//  CloudModelEditorController.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/26/25.
//

import AlertController
import Combine
import ConfigurableKit
import Storage
import UIKit

class CloudModelEditorController: StackScrollController {
    let identifier: CloudModel.ID

    var cancellables: Set<AnyCancellable> = .init()
    weak var responseFormatInfoView: ConfigurableInfoView?
    let serverModelListLoader = ServerModelListLoader()

    init(identifier: CloudModel.ID) {
        self.identifier = identifier
        super.init(nibName: nil, bundle: nil)
        title = String(localized: "Edit Model")
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        cancellables.forEach { $0.cancel() }
        cancellables.removeAll()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .background
        navigationItem.rightBarButtonItems = buildNavBarItems()

        ModelManager.shared.cloudModels
            .removeDuplicates()
            .ensureMainThread()
            .delay(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] values in
                guard let self, isVisible else { return }
                guard values.contains(where: { $0.id == self.identifier }) else {
                    navigationController?.popViewController(animated: true)
                    return
                }
            }
            .store(in: &cancellables)

        // Prefetch so the Model Identifier menu usually has the server list on first open.
        if let model = ModelManager.shared.cloudModel(identifier: identifier) {
            _ = serverModelListLoader.load(.init(model: model))
        }
    }

    override func setupContentViews() {
        super.setupContentViews()
        renderContent()
    }

    @objc func checkTapped() {
        navigationController?.popViewController()
    }
}

private extension CloudModelEditorController {
    func buildNavBarItems() -> [UIBarButtonItem] {
        let confirmItem = UIBarButtonItem(
            image: UIImage(systemName: "checkmark"),
            style: .done,
            target: self,
            action: #selector(checkTapped),
        )
        let actionsItem = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: nil,
            action: nil,
        )
        actionsItem.accessibilityLabel = String(localized: "More Actions")
        actionsItem.menu = buildActionsMenu()
        return [confirmItem, actionsItem]
    }
}

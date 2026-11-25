// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeListPage.swift), whose
// layout is copied from Irisin's WelcomeRepositoriesController.
//
//  WelcomeListPage.swift
//  FlowDown
//

import SnapKit
import UIKit

/// An inset grouped table over the fixed action bar. Subclasses supply the
/// rows and the action for their step of the welcome.
class WelcomeListPage: UIViewController, UITableViewDelegate {
    let tableView = UITableView(frame: .zero, style: .insetGrouped)
    let flow: WelcomeFlow
    private var action: (() -> Void)?
    private(set) lazy var actionBar = WelcomeActionBar(
        title: String(localized: "Next"),
        action: { [weak self] in self?.action?() },
    )

    init(flow: WelcomeFlow) {
        self.flow = flow
        super.init(nibName: nil, bundle: nil)
        // A small centered title, as on Irisin's second page.
        navigationItem.largeTitleDisplayMode = .never
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(flow:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = WelcomeStyle.groupedBackground
        view.addSubview(tableView)
        view.addSubview(actionBar)
        tableView.snp.makeConstraints {
            $0.top.leading.trailing.equalToSuperview()
            $0.bottom.equalTo(actionBar.snp.top)
        }
        actionBar.snp.makeConstraints { $0.leading.trailing.bottom.equalToSuperview() }
        tableView.backgroundColor = WelcomeStyle.groupedBackground
        tableView.delegate = self
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }

    func next(_ action: @escaping () -> Void) {
        self.action = action
    }

    /// Header or footer text in the list's own style.
    func text(_ configuration: UIListContentConfiguration, _ text: String) -> UIView {
        var configuration = configuration
        configuration.text = text
        let view = UITableViewHeaderFooterView()
        view.contentConfiguration = configuration
        return view
    }
}

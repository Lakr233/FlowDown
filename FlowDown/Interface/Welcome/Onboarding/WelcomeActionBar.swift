// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeActionBar.swift, itself
// copied from Irisin). FlowDown keeps no secondary action, uses SnapKit
// without Then, and keeps its own Mac inset of 16 around the button.
//
//  WelcomeActionBar.swift
//  FlowDown
//

import SnapKit
import UIKit

/// The bar under every onboarding page: a rule over a blur, and the page's
/// button.
final class WelcomeActionBar: UIView {
    private let button = UIButton(type: .system)
    private let rule = UIView()
    private var action: (() -> Void)?

    var title: String {
        get { button.configuration?.title ?? "" }
        set { button.configuration?.title = newValue }
    }

    var isEnabled: Bool {
        get { button.isEnabled }
        set { button.isEnabled = newValue }
    }

    func activate() {
        guard button.isEnabled else { return }
        action?()
    }

    init(title: String, action: @escaping () -> Void) {
        super.init(frame: .zero)
        self.action = action
        let blur = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        rule.backgroundColor = .separator
        addSubview(blur)
        addSubview(rule)
        addSubview(button)

        blur.snp.makeConstraints { x in
            x.edges.equalToSuperview()
        }
        rule.snp.makeConstraints { x in
            x.top.leading.trailing.equalToSuperview()
            x.height.equalTo(0.5)
        }
        button.snp.makeConstraints { x in
            #if targetEnvironment(macCatalyst)
                x.top.equalTo(rule.snp.bottom).offset(16)
                x.leading.trailing.bottom.equalToSuperview().inset(16)
            #else
                x.top.equalTo(rule.snp.bottom).offset(12)
                x.leading.trailing.equalToSuperview().inset(WelcomeStyle.horizontalMargin)
                x.bottom.equalTo(safeAreaLayoutGuide).inset(28)
            #endif
            // 48 tall, and taller when Dynamic Type grows the title
            x.height.greaterThanOrEqualTo(48)
        }

        button.layer.cornerRadius = 12
        button.clipsToBounds = true
        button.titleLabel?.font = WelcomeStyle.buttonFont
        var configuration = UIButton.Configuration.filled()
        configuration.cornerStyle = .large
        configuration.baseBackgroundColor = WelcomeStyle.accent
        configuration.baseForegroundColor = WelcomeStyle.accentForeground
        configuration.title = title
        button.configuration = configuration
        button.addAction(UIAction { [weak self] _ in self?.activate() }, for: .touchUpInside)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }
}

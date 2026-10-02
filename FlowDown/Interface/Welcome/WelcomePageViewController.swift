//
//  WelcomePageViewController.swift
//  Extracted reusable welcome screen
//
//  Created by ChatGPT on 2025/12/07.
//

import AlertController
import ColorfulX
import SnapKit
import SwifterSwift
import UIKit

/// A self-contained welcome screen that does not depend on the original app infrastructure.
/// - Shows an optional app icon, two-line title, feature list, and a primary action button.
/// - Uses only UIKit + SnapKit + SwifterSwift so it can be dropped into another project.
class WelcomePageViewController: UIViewController {
    var onComplete: (() -> Void)?

    let config: Configuration
    let scrollView = UIScrollView()
    let contentView = UIView()
    let stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 18
        stack.alignment = .fill
        stack.distribution = .fillProportionally
        return stack
    }()

    let ourColorView = AnimatedMulticolorGradientView().with { view in
        view.setColors(
            [
                .accent,
                .accent,
                .clear, .clear, .clear,
                .clear, .clear, .clear,
            ],
            animated: false
        )
        view.renderScale = 0.1
        view.noise = 0
        view.speed /= 2
        view.frameLimit = 30
    }

    let actionContainer = UIView()
    let actionButton = UIButton(type: .system)
    var featureViews: [FeatureRowView] = []

    let contentInsets = UIEdgeInsets(top: 28, left: 24, bottom: 28, right: 24)

    init(config: Configuration = .default, onComplete: (() -> Void)? = nil) {
        self.config = config
        self.onComplete = onComplete
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .formSheet
        modalTransitionStyle = .coverVertical
        isModalInPresentation = true
        preferredContentSize = .init(width: 520, height: 620)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        view.tintColor = config.accentColor
        setupLayout()
        applyConfiguration()

        ourColorView.alpha = 0.1
        view.addSubview(ourColorView)
        view.sendSubviewToBack(ourColorView)
        ourColorView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: false)
        navigationController?.view.tintColor = config.accentColor
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateFeatures()
    }

    private func setupLayout() {
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        view.addSubview(actionContainer)
        actionContainer.addSubview(actionButton)

        scrollView.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.edges.equalToSuperview()
            #else
                make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
                make.bottom.equalTo(actionContainer.snp.top)
            #endif
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(contentInsets)
        }

        let effect = UIVisualEffectView(effect: UIBlurEffect(style: .regular))
        actionContainer.addSubview(effect)
        actionContainer.sendSubviewToBack(effect)
        effect.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        actionContainer.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }

        let separator = UIView()
        separator.backgroundColor = .separator
        actionContainer.addSubview(separator)
        separator.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.height.equalTo(0.5)
        }

        actionButton.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.edges.equalToSuperview().inset(16)
            #else
                make.top.equalTo(separator.snp.bottom).offset(12)
                make.leading.trailing.equalToSuperview().inset(contentInsets.left)
                make.bottom.equalTo(view.safeAreaLayoutGuide).inset(contentInsets.bottom)
            #endif
            make.height.equalTo(48)
        }

        actionButton.layer.cornerRadius = 12
        actionButton.clipsToBounds = true
        actionButton.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        actionButton.addTarget(self, action: #selector(handleComplete), for: .touchUpInside)
    }

    private func applyConfiguration() {
        for view in stackView.arrangedSubviews {
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        featureViews.removeAll()

        let iconContainer = UIView()
        let iconView = UIImageView(image: config.icon)
        iconContainer.addSubview(iconView)
        iconView.contentMode = .scaleAspectFill
        iconView.layer.cornerRadius = 14
        iconView.layer.cornerCurve = .continuous
        iconView.addShadow(ofColor: .black, radius: 4, offset: CGSize(width: 0, height: 0), opacity: 0.1)
        iconView.clipsToBounds = true
        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(64)
            make.center.equalToSuperview()
            make.height.equalToSuperview()
        }
        stackView.addArrangedSubview(iconContainer)
        stackView.setCustomSpacing(12, after: iconView)

        let titleLabel = UILabel()
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .left
        let titleText = NSMutableAttributedString(
            string: String(localized: config.title),
            attributes: [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.label,
            ],
        )
        titleText.append(NSAttributedString(
            string: "\n" + String(localized: config.highlightedTitle),
            attributes: [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: config.accentColor,
            ],
        ))
        titleLabel.attributedText = titleText
        stackView.addArrangedSubview(titleLabel)

        let subtitleLabel = UILabel()
        subtitleLabel.text = String(localized: config.subtitle)
        subtitleLabel.font = .preferredFont(forTextStyle: .body)
        subtitleLabel.textColor = .secondaryLabel
        subtitleLabel.numberOfLines = 0
        stackView.addArrangedSubview(subtitleLabel)

        let separator = UIView()
        separator.backgroundColor = .separator
        separator.snp.makeConstraints { make in
            make.height.equalTo(0.75)
        }
        stackView.addArrangedSubview(separator)

        for (index, feature) in config.features.enumerated() {
            let row = FeatureRowView()
            row.configure(feature: feature, accentColor: config.accentColor)
            row.alpha = 0
            featureViews.append(row)
            stackView.addArrangedSubview(row)
            if index != config.features.indices.last {
                stackView.setCustomSpacing(10, after: row)
            }
        }

        let spacer = UIView()
        spacer.snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(12)
        }
        stackView.addArrangedSubview(spacer)

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.cornerStyle = .large
        buttonConfig.baseBackgroundColor = config.accentColor
        buttonConfig.baseForegroundColor = .white
        buttonConfig.title = String(localized: config.buttonTitle)
        actionButton.configuration = buttonConfig
    }

    @objc
    private func handleComplete() {
        onComplete?()
        onComplete = nil
        dismiss(animated: true)
    }

    private func animateFeatures() {
        for (idx, view) in featureViews.enumerated() {
            let delay = 0.1 * Double(idx)
            UIView.animate(
                withDuration: 0.5,
                delay: delay,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.4,
                options: [.curveEaseInOut],
            ) {
                view.alpha = 1
            }
        }
    }
}

extension WelcomePageViewController {
    static func makePresentedController(
        config: Configuration = .default,
        onComplete: (() -> Void)? = nil,
    ) -> UIViewController {
        let controller = WelcomePageViewController(config: config, onComplete: onComplete)
        controller.navigationItem.largeTitleDisplayMode = .never

        let navigationController = UINavigationController(rootViewController: controller)
        navigationController.navigationBar.prefersLargeTitles = false
        navigationController.view.backgroundColor = .systemBackground
        navigationController.view.tintColor = config.accentColor
        navigationController.navigationBar.tintColor = config.accentColor
        navigationController.isModalInPresentation = true

        let preferredWidth = controller.preferredContentSize.width
        let preferredHeight = controller.preferredContentSize.height

        #if targetEnvironment(macCatalyst)
            return AlertBaseController(
                rootViewController: navigationController,
                preferredWidth: preferredWidth,
                preferredHeight: preferredHeight,
            )
        #else
            navigationController.modalTransitionStyle = .coverVertical
            navigationController.modalPresentationStyle = .formSheet
            navigationController.preferredContentSize = .init(
                width: preferredWidth,
                height: preferredHeight,
            )
            return navigationController
        #endif
    }
}

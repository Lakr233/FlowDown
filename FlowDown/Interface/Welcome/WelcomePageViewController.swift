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

/// The first page of the welcome flow (`WelcomeFlow`).
/// - Shows the app icon, two-line title, feature list, and the flow's action bar.
class WelcomePageViewController: UIViewController {
    private let onNext: () -> Void

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

    private(set) lazy var actionBar = WelcomeActionBar(
        title: String(localized: config.buttonTitle),
    ) { [weak self] in
        self?.onNext()
    }

    var featureViews: [FeatureRowView] = []
    private var hasAppeared = false

    let contentInsets = UIEdgeInsets(top: 28, left: 24, bottom: 28, right: 24)

    init(config: Configuration = .default, onNext: @escaping () -> Void) {
        self.config = config
        self.onNext = onNext
        super.init(nibName: nil, bundle: nil)
        isModalInPresentation = true
        preferredContentSize = WelcomeFlow.preferredSize
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
        // Hidden at once when the sheet opens; back from the next page, the
        // bar leaves with the pop.
        navigationController?.setNavigationBarHidden(true, animated: animated && hasAppeared)
        hasAppeared = true
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

        view.addSubview(actionBar)

        scrollView.snp.makeConstraints { make in
            #if targetEnvironment(macCatalyst)
                make.edges.equalToSuperview()
            #else
                make.top.leading.trailing.equalTo(view.safeAreaLayoutGuide)
                make.bottom.equalTo(actionBar.snp.top)
            #endif
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }

        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(contentInsets)
        }

        actionBar.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
        }
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
        let title = String(localized: config.title)
        let titleText = NSMutableAttributedString(
            string: title,
            attributes: [
                .font: UIFont.systemFont(ofSize: 32, weight: .bold),
                .foregroundColor: UIColor.label,
            ],
        )
        if !config.highlightedTitle.isEmpty,
           let range = title.range(of: config.highlightedTitle, options: .backwards)
        {
            titleText.addAttribute(
                .foregroundColor,
                value: config.accentColor,
                range: NSRange(range, in: title),
            )
        }
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
    }

    private func animateFeatures() {
        guard !UIAccessibility.isReduceMotionEnabled else {
            featureViews.forEach { $0.alpha = 1 }
            return
        }
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

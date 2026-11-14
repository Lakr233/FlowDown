//
//  StackScrollController.swift
//  ConfigurableKit
//
//  Created by 秋星桥 on 2025/1/4.
//

import UIKit

open class StackScrollController: UIViewController {
    public let scrollView = UIScrollView()
    public let contentView = UIView()
    public let stackView = UIStackView()

    /// On iOS 26 and later the scroll view runs up under the bar (to the top
    /// of the view) so that what scrolls passes through the system's soft
    /// scroll edge effect instead of being cut off at the bar's bottom. The
    /// safe area's top becomes a content inset, so the page rests exactly
    /// where it did when the scroll view started below the bar.
    private let scrollsUnderTopBar = FloatingChrome.usesSystemScrollEdge
    private var appliedTopInset: CGFloat = 0

    override open func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .background

        stackView.axis = .vertical
        stackView.spacing = 0
        stackView.distribution = .equalSpacing

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(stackView)

        scrollView.clipsToBounds = true
        scrollView.alwaysBounceVertical = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.translatesAutoresizingMaskIntoConstraints = false
        stackView.translatesAutoresizingMaskIntoConstraints = false

        scrollView.contentInset = .init(top: 0, left: 0, bottom: 32, right: 0)

        scrollView.snp.makeConstraints { make in
            if scrollsUnderTopBar {
                make.top.equalToSuperview()
            } else {
                make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            }
            make.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.bottom)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
            if scrollsUnderTopBar {
                // As tall as the scroll view was when it started below the
                // bar, so short pages scroll no further than before.
                make.height.greaterThanOrEqualTo(view.safeAreaLayoutGuide)
            } else {
                make.height.greaterThanOrEqualToSuperview()
            }
        }

        if scrollsUnderTopBar {
            setContentScrollView(scrollView, for: .top)
            FloatingChrome.configureTopEdge(of: scrollView)
            updateTopInset()
        }

        stackView.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.lessThanOrEqualToSuperview()
        }

        view.hideKeyboardWhenTappedAround()

        setupContentViews()
        stackView
            .subviews
            .compactMap { view -> SeparatorView? in
                if view is SeparatorView {
                    return view as? SeparatorView
                }
                return nil
            }.forEach {
                $0.translatesAutoresizingMaskIntoConstraints = false
                NSLayoutConstraint.activate([
                    $0.heightAnchor.constraint(equalToConstant: 1),
                    $0.widthAnchor.constraint(equalTo: stackView.widthAnchor),
                ])
            }
    }

    override open func viewSafeAreaInsetsDidChange() {
        super.viewSafeAreaInsetsDidChange()
        updateTopInset()
    }

    /// Keeps the content inset's top equal to the safe area's (the bar's
    /// height), moving the offset with it so the content stays where it is
    /// on screen.
    private func updateTopInset() {
        guard scrollsUnderTopBar else { return }
        let topInset = view.safeAreaInsets.top
        let delta = topInset - appliedTopInset
        guard delta != 0 else { return }
        appliedTopInset = topInset
        let offset = scrollView.contentOffset.y - delta
        scrollView.contentInset.top += delta
        scrollView.contentOffset.y = offset
    }

    open func setupContentViews() { /* stub */ }
}

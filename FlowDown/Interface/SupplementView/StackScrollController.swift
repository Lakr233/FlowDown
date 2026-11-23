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

    /// Where `FloatingChrome.usesSystemScrollEdge` (never, today) the scroll
    /// view runs up under the bar (to the top of the view) so that what scrolls passes through the system's soft
    /// scroll edge effect instead of being cut off at the bar's bottom. The
    /// safe area's top becomes a content inset, so the page rests exactly
    /// where it did when the scroll view started below the bar.
    private let scrollsUnderTopBar = FloatingChrome.usesSystemScrollEdge
    private var appliedTopInset: CGFloat = 0
    private var appliedBottomInset: CGFloat = 0
    /// How much of the view the software keyboard covers, in points.
    private var keyboardOverlap: CGFloat = 0

    override open func viewDidLoad() {
        super.viewDidLoad()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillChangeFrameNotification,
            object: nil,
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardFrameWillChange(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil,
        )

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
            // Side insets can differ on iPhone Duo, where the status area
            // and system bars can stand along one edge.
            make.leading.equalTo(view.safeAreaLayoutGuide.snp.leading)
            make.trailing.equalTo(view.safeAreaLayoutGuide.snp.trailing)
            // The scroll view runs to the bottom of the view so rows scroll
            // under the home indicator instead of being cut off at a hard
            // line above it. The bottom safe area becomes a content inset.
            make.bottom.equalToSuperview()
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
            // As tall as the safe area, which is what the scroll view spanned
            // when it stopped at both safe edges, so short pages scroll no
            // further than before.
            make.height.greaterThanOrEqualTo(view.safeAreaLayoutGuide)
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
        updateBottomInset()
    }

    /// Keeps the last row clear of the home indicator at the end of the page,
    /// or of the keyboard while it is up.
    private func updateBottomInset() {
        let bottomInset = max(view.safeAreaInsets.bottom, keyboardOverlap)
        let delta = bottomInset - appliedBottomInset
        guard delta != 0 else { return }
        appliedBottomInset = bottomInset
        scrollView.contentInset.bottom += delta
        scrollView.verticalScrollIndicatorInsets.bottom += delta
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

    @objc private func keyboardFrameWillChange(_ notification: Notification) {
        var overlap: CGFloat = 0
        if notification.name != UIResponder.keyboardWillHideNotification,
           let screen = view.window?.windowScene?.screen,
           let endFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        {
            let keyboardFrame = view.convert(endFrame, from: screen.coordinateSpace)
            let covered = view.bounds.intersection(keyboardFrame)
            overlap = covered.isNull ? 0 : covered.height
        }
        guard overlap != keyboardOverlap else { return }
        keyboardOverlap = overlap
        updateBottomInset()
        guard overlap > 0, let responder = firstResponder(in: scrollView) else { return }
        scrollView.layoutIfNeeded()
        // A field taller than the space above the keyboard keeps its top in
        // view, so its first line is not pushed under the navigation bar.
        let inset = scrollView.adjustedContentInset
        let visibleHeight = scrollView.bounds.height - inset.top - inset.bottom
        var target = responder.convert(responder.bounds, to: scrollView)
        target.size.height = min(target.height, max(visibleHeight, 0))
        scrollView.scrollRectToVisible(target, animated: true)
    }

    private func firstResponder(in view: UIView) -> UIView? {
        if view.isFirstResponder { return view }
        for subview in view.subviews {
            if let found = firstResponder(in: subview) { return found }
        }
        return nil
    }

    open func setupContentViews() { /* stub */ }
}

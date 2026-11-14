//
//  Sidebar.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/21/25.
//

import SnapKit
import Storage
import UIKit

class Sidebar: UIView {
    let brandingLabel = SidebarBrandingLabel()
    let newChatButton = NewChatButton()
    let searchButton = SearchControllerOpenButton()
    let settingButton = SettingButton()
    let conversationSelectionView = ConversationSelectionView()
    let syncIndicator = SidebarSyncLabel()

    #if !targetEnvironment(macCatalyst)
        /// The soft edge under the header before iOS 26: from the top of
        /// the screen to 16 pt below the new-chat button, clear of the first
        /// row at rest. The list runs up under it instead of stopping hard
        /// below the header. Absent on iOS 26 and later, where the list's
        /// own scroll edge effect is the edge (`topEdgeElements`).
        let topEdgeBlur: ProgressiveBlurView? = FloatingChrome.usesSystemScrollEdge ? nil : ProgressiveBlurView()
        /// On iOS 26 and later: holds the branding label and the new-chat
        /// button, so the system runs the list's soft top edge under them.
        private let topEdgeElements: FloatingChromeElementContainer? =
            FloatingChrome.usesSystemScrollEdge ? FloatingChromeElementContainer() : nil
        private var listTopConstraint: Constraint?
        private let spacing: CGFloat = 16
    #endif

    init() {
        super.init(frame: .zero)

        let spacing: CGFloat = 16

        #if !targetEnvironment(macCatalyst)
            // Under the header: the list, then the soft edge over it.
            addSubview(conversationSelectionView)
            if let topEdgeBlur {
                addSubview(topEdgeBlur)
            }
        #endif

        #if targetEnvironment(macCatalyst)
            addSubview(brandingLabel)
            addSubview(newChatButton)
        #else
            let newChatButtonSurface = newChatButton.wrappedInFloatingButtonSurface()
            if let topEdgeElements {
                addSubview(topEdgeElements)
                topEdgeElements.addSubview(brandingLabel)
                topEdgeElements.addSubview(newChatButtonSurface)
            } else {
                addSubview(brandingLabel)
                addSubview(newChatButtonSurface)
            }
        #endif
        addSubview(settingButton)
        addSubview(searchButton)
        addSubview(syncIndicator)

        newChatButton.delegate = self
        #if targetEnvironment(macCatalyst)
            brandingLabel.snp.makeConstraints { make in
                make.left.top.equalToSuperview()
                make.right.equalTo(newChatButton).offset(-spacing)
            }
            newChatButton.snp.makeConstraints { make in
                make.right.equalToSuperview()
                make.width.height.equalTo(32)
                make.centerY.equalTo(brandingLabel.snp.centerY)
            }
        #else
            // The floating button keeps the old 32 pt button's centre line
            // and trailing edge; the branding row grows to its 44 pt.
            newChatButtonSurface.snp.makeConstraints { make in
                make.right.equalToSuperview()
                make.width.height.equalTo(FloatingChrome.buttonSize)
                make.centerY.equalTo(brandingLabel.snp.centerY)
            }
            // The header row's frame, in the sidebar: the container changes
            // nothing about where the label and the button stand.
            topEdgeElements?.snp.makeConstraints { make in
                make.left.top.right.equalToSuperview()
                make.bottom.greaterThanOrEqualTo(brandingLabel)
                make.bottom.greaterThanOrEqualTo(newChatButtonSurface)
                make.bottom.equalTo(newChatButtonSurface).priority(.high)
            }
            brandingLabel.snp.makeConstraints { make in
                make.left.top.equalToSuperview()
                make.right.equalTo(newChatButtonSurface.snp.left).offset(-spacing)
            }
        #endif

        settingButton.snp.makeConstraints { make in
            make.left.bottom.equalToSuperview()
            make.width.height.equalTo(32)
        }
        searchButton.snp.makeConstraints { make in
            make.width.height.equalTo(32)
            make.right.bottom.equalToSuperview()
        }

        searchButton.delegate = self

        #if targetEnvironment(macCatalyst)
            addSubview(conversationSelectionView)
            conversationSelectionView.snp.makeConstraints { make in
                make.top.equalTo(brandingLabel.snp.bottom).offset(spacing)
                make.bottom.equalTo(settingButton.snp.top).offset(-spacing)
                make.left.right.equalToSuperview()
            }
        #else
            conversationSelectionView.tableView.contentInsetAdjustmentBehavior = .never
            FloatingChrome.configureTopEdge(of: conversationSelectionView.tableView)
            if let topEdgeElements {
                FloatingChrome.addTopEdgeElements(in: topEdgeElements, over: conversationSelectionView.tableView)
            }
            conversationSelectionView.snp.makeConstraints { make in
                listTopConstraint = make.top.equalToSuperview().constraint
                make.bottom.equalTo(settingButton.snp.top).offset(-spacing)
                make.left.right.equalToSuperview()
            }
        #endif

        syncIndicator.snp.makeConstraints { make in
            make.bottom.equalToSuperview()
            make.left.equalTo(settingButton.snp.right).offset(8)
            make.right.equalTo(searchButton.snp.left).offset(-8)
            make.height.equalTo(32)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    #if !targetEnvironment(macCatalyst)
        override func layoutSubviews() {
            super.layoutSubviews()
            // The header is one level down on iOS 26 and later; its frames
            // are read below, so it is laid out first.
            topEdgeElements?.layoutIfNeeded()

            // The list and the edge reach up to the top of the screen, past
            // the column's own top inset (the column does not clip them).
            let overshoot = max(0, window.map { convert(bounds.origin, to: $0).y } ?? 0)
            let headerBottom = brandingLabel.frame.maxY
            let buttonBottom = newChatButton.convert(newChatButton.bounds, to: self).maxY

            if listTopConstraint?.layoutConstraints.first?.constant != -overshoot {
                listTopConstraint?.update(offset: -overshoot)
                setNeedsLayout()
            }

            // The first row rests where it always did, below the header.
            let tableView = conversationSelectionView.tableView
            let topInset = overshoot + headerBottom + spacing
            if tableView.contentInset.top != topInset {
                let atTop = tableView.contentOffset.y <= -tableView.adjustedContentInset.top + 1
                tableView.contentInset.top = topInset
                tableView.verticalScrollIndicatorInsets.top = topInset
                if atTop {
                    tableView.contentOffset.y = -topInset
                }
            }

            guard let topEdgeBlur else { return }

            // The column sits inset from the screen's sides; the edge spans
            // the whole width so no unblurred strip shows beside it (the
            // part to the right lies under the chat card).
            var leading: CGFloat = 0
            var trailing: CGFloat = 0
            if let window {
                let frameInWindow = convert(bounds, to: window)
                leading = max(0, frameInWindow.minX)
                trailing = max(0, window.bounds.width - frameInWindow.maxX)
            }

            topEdgeBlur.layoutAsBarEdge(CGRect(
                x: -leading,
                y: -overshoot,
                width: leading + bounds.width + trailing,
                height: FloatingChrome.pageEdgeHeight(controlBottom: overshoot + buttonBottom),
            ))
        }
    #endif
}

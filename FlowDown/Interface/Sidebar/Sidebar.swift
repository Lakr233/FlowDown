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
        /// The soft edge under the header: from the top of the screen to the
        /// bottom of the new-chat button, then 14 pt and a 28 pt tail. The
        /// list runs up under it instead of stopping hard below the header.
        let topEdgeBlur = ProgressiveBlurView()
        private var listTopConstraint: Constraint?
        private let spacing: CGFloat = 16
    #endif

    init() {
        super.init(frame: .zero)

        let spacing: CGFloat = 16

        #if !targetEnvironment(macCatalyst)
            // Under the header: the list, then the soft edge over it.
            addSubview(conversationSelectionView)
            addSubview(topEdgeBlur)
        #endif

        addSubview(brandingLabel)
        #if targetEnvironment(macCatalyst)
            addSubview(newChatButton)
        #else
            let newChatButtonSurface = newChatButton.wrappedInFloatingButtonSurface()
            addSubview(newChatButtonSurface)
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
            FloatingChrome.hideSystemTopEdge(of: conversationSelectionView.tableView)
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

            topEdgeBlur.layoutAsBarEdge(CGRect(
                x: 0,
                y: -overshoot,
                width: bounds.width,
                height: FloatingChrome.topEdgeHeight(buttonBottom: overshoot + buttonBottom),
            ))
        }
    #endif
}

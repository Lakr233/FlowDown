//
//  ConversationSelectionView+Cell.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/5/25.
//

import AlertController
import Storage
import UIKit

extension ConversationSelectionView {
    class Cell: UITableViewCell, UIContextMenuInteractionDelegate {
        let stack = UIStackView().with {
            $0.axis = .horizontal
            $0.spacing = 12
            $0.alignment = .center
            $0.distribution = .fill
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        let iconView = UIImageView().with {
            $0.contentMode = .scaleAspectFit
            $0.image = UIImage(systemName: "doc.text")
            $0.tintColor = .accent
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.snp.makeConstraints { make in
                make.width.height.equalTo(28)
            }
        }

        let titleLabel = UILabel().with {
            $0.font = .preferredFont(forTextStyle: .body)
            $0.textColor = .label
            $0.numberOfLines = 1
            $0.textAlignment = .left
            $0.translatesAutoresizingMaskIntoConstraints = false
        }

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)
            stack.addArrangedSubview(iconView)
            stack.addArrangedSubview(titleLabel)
            contentView.addSubview(stack)

            backgroundColor = .clear
            separatorInset = .zero

            let selectionColor = UIView().with {
                $0.backgroundColor = .accent.withAlphaComponent(0.15)
                $0.layer.cornerRadius = 12
            }
            selectedBackgroundView = selectionColor

            stack.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(UIEdgeInsets(horizontal: 24, vertical: 16))
            }

            contentView.isUserInteractionEnabled = true
            let tap = UITapGestureRecognizer(target: self, action: #selector(didSelectCell))
            contentView.addGestureRecognizer(tap)
            #if targetEnvironment(macCatalyst)
                contentView.backgroundColor = .accent.withAlphaComponent(0.001)
            #endif

            let contextMenuInteraction = UIContextMenuInteraction(delegate: self)
            contentView.addInteraction(contextMenuInteraction)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        private var conversationIdentifier: Conversation.ID?

        func use(_ conv: Conversation?) {
            conversationIdentifier = conv?.id
            guard let conv else {
                titleLabel.text = nil
                iconView.image = UIImage(systemName: "doc.text")
                return
            }
            titleLabel.text = conv.title
            iconView.image = conv.interfaceImage
        }

        func contextMenuInteraction(
            _: UIContextMenuInteraction,
            configurationForMenuAtLocation _: CGPoint,
        ) -> UIContextMenuConfiguration? {
            guard let conversationIdentifier else { return nil }

            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
                guard let self else { return nil }
                return ConversationManager.shared.menu(
                    forConversation: conversationIdentifier,
                    view: self,
                )
            }
        }

        @objc func didSelectCell() {
            guard let id = conversationIdentifier else { return }
            Logger.ui.debugFile("did select conversation cell: \(id)")
            ChatSelection.shared.select(id, options: [.collapseSidebar])
        }
    }
}

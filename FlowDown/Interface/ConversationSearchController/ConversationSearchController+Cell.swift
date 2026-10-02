//
//  ConversationSearchController+Cell.swift
//  FlowDown
//
//  Created by Alan Ye on 7/8/25.
//

import Storage
import UIKit

extension SearchContentController {
    class SearchResultCell: UITableViewCell {
        let iconView = UIImageView()
        let titleLabel = UILabel()
        let subtitleLabel = UILabel()
        let dateLabel = UILabel()
        let stackView = UIStackView()
        let textStackView = UIStackView()
        let titleDateStackView = UIStackView()

        override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
            super.init(style: style, reuseIdentifier: reuseIdentifier)

            backgroundColor = .clear

            iconView.contentMode = .scaleAspectFit
            iconView.layer.cornerRadius = 6
            iconView.clipsToBounds = true
            iconView.snp.makeConstraints { make in
                make.width.height.equalTo(28)
            }

            titleLabel.font = .preferredFont(forTextStyle: .body)
            titleLabel.textColor = .label
            titleLabel.numberOfLines = 1
            titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            titleLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

            dateLabel.font = .preferredFont(forTextStyle: .body)
            dateLabel.textColor = .secondaryLabel
            dateLabel.setContentHuggingPriority(.required, for: .horizontal)
            dateLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
            dateLabel.numberOfLines = 1

            titleDateStackView.axis = .horizontal
            titleDateStackView.spacing = 8
            titleDateStackView.alignment = .center
            titleDateStackView.distribution = .fill
            titleDateStackView.addArrangedSubview(titleLabel)
            titleDateStackView.addArrangedSubview(dateLabel)

            subtitleLabel.font = .preferredFont(forTextStyle: .body)
            subtitleLabel.textColor = .secondaryLabel
            subtitleLabel.numberOfLines = 2

            textStackView.axis = .vertical
            textStackView.spacing = 8
            textStackView.addArrangedSubview(titleDateStackView)

            stackView.axis = .horizontal
            stackView.spacing = 8
            stackView.alignment = .center
            stackView.addArrangedSubview(iconView)
            stackView.addArrangedSubview(textStackView)
            textStackView.addArrangedSubview(subtitleLabel)

            contentView.addSubview(stackView)
            stackView.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(16)
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func prepareForReuse() {
            super.prepareForReuse()
            backgroundColor = .clear
            transform = .identity
            titleLabel.attributedText = nil
            titleLabel.text = nil
            subtitleLabel.attributedText = nil
        }

        func configure(with result: ConversationSearchResult, searchTerm: String, isHighlighted: Bool = false) {
            iconView.image = result.conversation.interfaceImage

            if result.matchType == .title, !searchTerm.isEmpty {
                titleLabel.attributedText = NSAttributedString.highlightedString(
                    text: result.conversation.title,
                    searchTerm: searchTerm,
                    baseAttributes: [.font: UIFont.preferredFont(forTextStyle: .body).bold],
                    highlightAttributes: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3)],
                )
            } else {
                titleLabel.text = result.conversation.title
            }

            dateLabel.text = formatDate(result.conversation.creation)

            if result.matchType == .message, let preview = result.messagePreview {
                subtitleLabel.isHidden = false

                let cleanedPreview = preview
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\n", with: " ")

                subtitleLabel.attributedText = NSAttributedString.highlightedString(
                    text: cleanedPreview,
                    searchTerm: searchTerm,
                    baseAttributes: [
                        .font: UIFont.preferredFont(forTextStyle: .body),
                        .foregroundColor: UIColor.secondaryLabel,
                    ],
                    highlightAttributes: [.backgroundColor: UIColor.systemYellow.withAlphaComponent(0.3)],
                )
            } else {
                subtitleLabel.isHidden = true
            }

            updateHighlightState(isHighlighted)
        }

        func updateHighlightState(_ isHighlighted: Bool) {
            let backgroundColor = isHighlighted ? UIColor.tintColor.withAlphaComponent(0.1) : .clear
            guard self.backgroundColor != backgroundColor else { return }

            UIView.animate(withDuration: 0.12, delay: 0, options: [.curveEaseInOut, .allowUserInteraction, .beginFromCurrentState]) {
                self.backgroundColor = backgroundColor
            }
        }

        private func formatDate(_ date: Date) -> String {
            let calendar = Calendar.current
            let now = Date()

            if calendar.isDateInToday(date) {
                let formatter = DateFormatter()
                formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "jm", options: 0, locale: Locale.current)
                return formatter.string(from: date)
            } else if calendar.isDateInYesterday(date) {
                return String(localized: "Yesterday")
            } else if let dayDifference = calendar.dateComponents([.day], from: date, to: now).day, dayDifference < 7 {
                let formatter = DateFormatter()
                formatter.dateFormat = DateFormatter.dateFormat(
                    fromTemplate: "EEEE",
                    options: 0,
                    locale: Locale.current
                )
                return formatter.string(from: date)
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = DateFormatter.dateFormat(fromTemplate: "yMd", options: 0, locale: Locale.current)
                return formatter.string(from: date)
            }
        }
    }
}

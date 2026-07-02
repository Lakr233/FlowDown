//
//  Created by ktiays on 2025/2/21.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import GlyphixTextFx
import Litext
import UIKit

final class ReasoningContentView: MessageListRowView {
    private lazy var indicator: UIView = .init()
    private lazy var textView: TextLabelView = .init().with {
        $0.isSelectable = true
    }

    private lazy var thinkingTile: ThinkingTile = .init()

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = 3
        return style
    }()

    static let revealedTileHeight: CGFloat = 44
    static let unrevealedTileHeight: CGFloat = 70
    static let spacing: CGFloat = 12

    var thinkingDuration: TimeInterval = 0 {
        didSet {
            thinkingTile.thinkingDuration = thinkingDuration
        }
    }

    var thinkingTileTapHandler: ((_ newValue: Bool) -> Void)?

    var isRevealed: Bool = false {
        didSet { doWithAnimation { [self] in
            thinkingTile.isRevealed = isRevealed
            setNeedsLayout()
            layoutIfNeeded()
        }}
    }

    var isThinking: Bool = false {
        didSet { doWithAnimation { [self] in
            thinkingTile.isThinking = isThinking
            setNeedsLayout()
            layoutIfNeeded()
        } }
    }

    var text: String? {
        didSet {
            if let text {
                textView.attributedText = .init(string: text, attributes: [
                    .font: theme.fonts.footnote,
                    .foregroundColor: UIColor.secondaryLabel,
                    .paragraphStyle: Self.paragraphStyle,
                ])
            } else {
                textView.attributedText = .init()
            }
            let singleLineContent = text?.replacingOccurrences(of: "\n", with: " ")
            thinkingTile.thinkingContent = singleLineContent?.suffix(50)
                .map { String($0) }
                .joined()
            setNeedsLayout()
        }
    }

    override init(frame: CGRect) {
        var decisionFrame = frame
        if decisionFrame == .zero {
            // prevent unwanted animation with magic
            decisionFrame = .init(x: 0, y: 0, width: 512, height: 10)
        }
        super.init(frame: decisionFrame)

        contentView.clipsToBounds = true

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleThinkTileTap(_:)))
        thinkingTile.addGestureRecognizer(tapGesture)
        contentView.addSubview(thinkingTile)

        indicator.layer.cornerRadius = 1
        indicator.backgroundColor = .secondaryLabel
        indicator.alpha = 0.6
        contentView.addSubview(indicator)

        textView.backgroundColor = .clear
        contentView.addSubview(textView)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        thinkingTile.titleLabel.font = theme.fonts.body
        thinkingTile.thinkingContentFont = theme.fonts.footnote
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        thinkingTile.frame = .init(
            x: 0,
            y: 0,
            width: thinkingTile.intrinsicContentSize.width,
            height: isRevealed ? Self.revealedTileHeight : Self.unrevealedTileHeight,
        )

        let indicatorY = thinkingTile.frame.maxY + 12
        indicator.frame = .init(x: 0, y: indicatorY, width: 2, height: contentView.bounds.height - indicatorY)

        let textViewOrigin = CGPoint(
            x: indicator.frame.maxX + 14,
            y: indicator.frame.minY,
        )
        let textWidth = contentView.bounds.width - textViewOrigin.x
        textView.preferredMaxLayoutWidth = textWidth
        textView.frame = .init(
            x: textViewOrigin.x,
            y: textViewOrigin.y,
            width: textWidth,
            height: ceil(textView.intrinsicContentSize.height),
        )
        textView.alpha = isRevealed ? 1 : 0
    }

    @objc
    private func handleThinkTileTap(_: UITapGestureRecognizer) {
        thinkingTileTapHandler?(!isRevealed) // dont do it, otherwise content are flying
    }
}

extension ReasoningContentView {
    final class ThinkingTile: UIView {
        var thinkingDuration: TimeInterval = 0 {
            didSet {
                updateThinkingDurationText()
            }
        }

        var isRevealed: Bool = false {
            didSet {
                setNeedsLayout()
            }
        }

        var isThinking: Bool = true {
            didSet {
                loadingSymbol.isHidden = !isThinking
                setNeedsLayout()
            }
        }

        var thinkingContentFont: UIFont = .systemFont(ofSize: 12) {
            didSet {
                let content = thinkingContent
                thinkingContent = content // do update
            }
        }

        var thinkingContent: String? {
            didSet {
                if let content = thinkingContent {
                    textView.attributedText = .init(string: content, attributes: [
                        .font: thinkingContentFont,
                        .foregroundColor: UIColor.secondaryLabel,
                    ])
                } else {
                    textView.attributedText = .init()
                }
                if textView.bounds.width > 0 {
                    doWithAnimation { self.layoutTextView() }
                } else {
                    layoutTextView()
                }
            }
        }

        lazy var titleLabel: GlyphixTextLabel = .init().with {
            $0.isBlurEffectEnabled = false
        }

        private lazy var loadingSymbol: LoadingSymbol = .init()
        private lazy var textView: TextLabelView = .init()
        private lazy var textContainerView: UIView = .init()
        private lazy var arrowView: UIImageView = .init(
            image: UIImage(
                systemName: "chevron.right",
                withConfiguration: UIImage.SymbolConfiguration(scale: .small),
            ),
        ).with {
            $0.contentMode = .scaleAspectFit
        }

        override init(frame: CGRect) {
            super.init(frame: frame)
            clipsToBounds = true

            backgroundColor = .secondarySystemFill.withAlphaComponent(0.08)
            layer.cornerRadius = 14
            layer.cornerCurve = .continuous

            titleLabel.textAlignment = .leading
            addSubview(titleLabel)

            loadingSymbol.dotRadius = 1
            loadingSymbol.spacing = 2
            loadingSymbol.animationDuration = 0.4
            loadingSymbol.animationInterval = 0.1
            addSubview(loadingSymbol)

            textView.backgroundColor = .clear
            addSubview(textView)
            addSubview(textContainerView)
            textContainerView.addSubview(textView)

            // Create gradient mask using CAGradientLayer
            let gradientMask = CAGradientLayer()
            gradientMask.colors = [
                UIColor.black.cgColor,
                UIColor.black.withAlphaComponent(0).cgColor,
            ]
            gradientMask.startPoint = CGPoint(x: 0.8, y: 0.5)
            gradientMask.endPoint = CGPoint(x: 1.0, y: 0.5)
            textContainerView.layer.mask = gradientMask

            arrowView.tintColor = .label
            addSubview(arrowView)

            updateThinkingDurationText()
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            let titleSize = titleLabel.intrinsicContentSize
            titleLabel.frame = .init(
                x: 14,
                y: isRevealed ? (bounds.height - ceil(titleSize.height)) / 2 : 12,
                width: ceil(titleSize.width),
                height: ceil(titleSize.height),
            )
            loadingSymbol.frame = .init(
                x: titleLabel.frame.maxX + 3,
                y: titleLabel.frame.midY - 4.5,
                width: loadingSymbol.intrinsicContentSize.width,
                height: 9,
            )

            let arrowSize = arrowView.intrinsicContentSize
            arrowView.frame = .init(
                x: bounds.width - arrowSize.width - 12,
                y: (bounds.height - arrowSize.height) / 2,
                width: arrowSize.width,
                height: arrowSize.height,
            )

            layoutTextView()

            if isRevealed {
                textView.alpha = 0
                arrowView.transform = .init(rotationAngle: .pi / 2)
            } else {
                textView.alpha = 1
                arrowView.transform = .identity
            }
        }

        private func updateThinkingDurationText() {
            let text = String(localized: "Thought for \(Int(thinkingDuration)) seconds")
            titleLabel.text = text
        }

        override var intrinsicContentSize: CGSize {
            let titleSize = titleLabel.intrinsicContentSize
            return .init(
                width: titleSize.width + (isRevealed ? 80 : 180),
                height: titleSize.height,
            )
        }

        private func layoutTextView() {
            textView.preferredMaxLayoutWidth = .infinity
            let textSize = textView.intrinsicContentSize
            let textWidth = ceil(textSize.width)
            let textHeight = ceil(textSize.height)
            let rightPadding: CGFloat = 26
            textContainerView.frame = .init(
                x: 0,
                y: ReasoningContentView.unrevealedTileHeight - textHeight - 12,
                width: bounds.width - rightPadding,
                height: textHeight,
            )
            textContainerView.layer.mask?.frame = textContainerView.bounds
            textView.frame = .init(
                x: bounds.width - textWidth - rightPadding,
                y: 0,
                width: textWidth,
                height: textHeight,
            )
        }
    }
}

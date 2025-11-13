//
//  Created by ktiays on 2025/2/28.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import GlyphixTextFx
import UIKit

final class ToolHintView: MessageListRowView {
    enum State {
        case running
        case suceeded
        case failed
    }

    var text: String?

    var toolName: String = .init()

    var state: State = .running {
        didSet {
            updateContentText()
            updateStateImage()
        }
    }

    var clickHandler: (() -> Void)?

    private let backgroundGradientLayer = CAGradientLayer()
    private let label: ShimmerTextLabel = .init().with {
        $0.font = UIFont.preferredFont(forTextStyle: .body)
        $0.textColor = .label
        $0.minimumScaleFactor = 0.5
        $0.adjustsFontForContentSizeCategory = true
        $0.lineBreakMode = .byTruncatingTail
        $0.numberOfLines = 1
        $0.adjustsFontSizeToFitWidth = true
        $0.textAlignment = .left
        $0.animationDuration = 1.6
    }

    private let symbolView: UIImageView = .init().with {
        $0.contentMode = .scaleAspectFit
    }

    private let decoratedView: UIImageView = .init(image: .init(named: "tools"))
    private var isClickable: Bool = false
    private var cachedContentSize: CGSize = .zero

    override init(frame: CGRect) {
        super.init(frame: frame)

        decoratedView.contentMode = .scaleAspectFit
        decoratedView.tintColor = .label

        backgroundGradientLayer.startPoint = .init(x: 0.6, y: 0)
        backgroundGradientLayer.endPoint = .init(x: 0.4, y: 1)

        contentView.backgroundColor = .clear
        contentView.layer.cornerRadius = 12
        contentView.layer.cornerCurve = .continuous
        contentView.layer.insertSublayer(backgroundGradientLayer, at: 0)
        contentView.addSubview(decoratedView)
        contentView.addSubview(symbolView)
        contentView.addSubview(label)

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        contentView.addGestureRecognizer(tapGesture)

        updateStateImage()
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        let labelSize = label.intrinsicContentSize
        
        // Validate dimensions to prevent layout crashes
        guard labelSize.width > 0, labelSize.height > 0,
              contentView.bounds.height > 0 else {
            return
        }

        let symbolSize = labelSize.height
        let symbolX: CGFloat = 12
        let labelX = symbolX + symbolSize + 8
        let decoratedX = labelX + labelSize.width + 6
        
        // Calculate total width needed
        let totalWidth = decoratedX + 12
        
        // Update cached size for intrinsicContentSize
        cachedContentSize = CGSize(width: totalWidth, height: contentView.bounds.height)
        
        // Position subviews within contentView bounds
        let centerY = (contentView.bounds.height - labelSize.height) / 2

        symbolView.frame = CGRect(
            x: symbolX,
            y: centerY,
            width: symbolSize,
            height: symbolSize
        )

        label.frame = CGRect(
            x: labelX,
            y: centerY,
            width: min(labelSize.width, contentView.bounds.width - labelX - 18),
            height: labelSize.height
        )

        decoratedView.frame = CGRect(
            x: min(decoratedX, contentView.bounds.width - 12),
            y: -4,
            width: 16,
            height: 16
        )
        
        backgroundGradientLayer.frame = contentView.bounds
        backgroundGradientLayer.cornerRadius = contentView.layer.cornerRadius
    }
    
    override var intrinsicContentSize: CGSize {
        if cachedContentSize.width > 0 {
            return cachedContentSize
        }
        
        let labelSize = label.intrinsicContentSize
        guard labelSize.width > 0, labelSize.height > 0 else {
            return CGSize(width: UIView.noIntrinsicMetric, height: 44)
        }
        
        let totalWidth = 12 + labelSize.height + 8 + labelSize.width + 18
        return CGSize(width: totalWidth, height: 44)
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
    }

    private func updateStateImage() {
        let configuration = UIImage.SymbolConfiguration(scale: .small)
        switch state {
        case .suceeded:
            backgroundGradientLayer.colors = [
                UIColor.systemGreen.withAlphaComponent(0.08).cgColor,
                UIColor.systemGreen.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "checkmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemGreen
            label.stopShimmer()
        case .running:
            backgroundGradientLayer.colors = [
                UIColor.systemBlue.withAlphaComponent(0.08).cgColor,
                UIColor.systemBlue.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "hourglass", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemBlue
            label.startShimmer()
        default:
            backgroundGradientLayer.colors = [
                UIColor.systemRed.withAlphaComponent(0.08).cgColor,
                UIColor.systemRed.withAlphaComponent(0.12).cgColor,
            ]
            let image = UIImage(systemName: "xmark.seal", withConfiguration: configuration)
            symbolView.image = image
            symbolView.tintColor = .systemRed
            label.stopShimmer()
        }
        postUpdate()
    }

    private func updateContentText() {
        switch state {
        case .running:
            isClickable = false
            label.text = String(localized: "Tool call for \(toolName) running")
        case .suceeded:
            isClickable = true
            label.text = String(localized: "Tool call for \(toolName) completed.")
        case .failed:
            isClickable = true
            label.text = String(localized: "Tool call for \(toolName) failed.")
        }
        postUpdate()
    }

    func postUpdate() {
        label.invalidateIntrinsicContentSize()
        label.sizeToFit()
        cachedContentSize = .zero // Reset cached size to force recalculation
        invalidateIntrinsicContentSize()
        setNeedsLayout()

        doWithAnimation {
            self.layoutIfNeeded()
        }
    }

    @objc
    private func handleTap(_ sender: UITapGestureRecognizer) {
        if isClickable, sender.state == .ended {
            clickHandler?()
        }
    }
}

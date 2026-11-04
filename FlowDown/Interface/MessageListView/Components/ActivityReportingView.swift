//
//  Created by ktiays on 2025/2/20.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import UIKit

/// What the session is doing while a reply has not started, shimmering at
/// the reply's leading edge.
final class ActivityReportingView: MessageListRowView {
    /// An empty status, the session at work with nothing to report, reads
    /// "Thinking…".
    var text: String? {
        get { label.text }
        set {
            let text = newValue?.isEmpty == true ? String(localized: "Thinking…") : newValue
            label.text = text
            label.accessibilityLabel = text
        }
    }

    private let label = ThinkingStatusLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        label.animationIdentity = "ActivityReporting"
        label.isThinking = true
        label.onShownTextChange = { [weak self] in self?.setNeedsLayout() }
        contentView.addSubview(label)
    }

    @available(*, unavailable)
    @MainActor required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func themeDidUpdate() {
        super.themeDidUpdate()
        label.font = theme.fonts.body
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let bounds = contentView.bounds
        let width = min(bounds.width, label.shownTextWidth + 2)
        label.frame = contentView.directionalFrame(CGRect(
            x: 0,
            y: 0,
            width: width,
            height: Self.height(font: theme.fonts.body),
        ))
    }

    static func height(font: UIFont) -> CGFloat {
        ceil(font.lineHeight)
    }
}

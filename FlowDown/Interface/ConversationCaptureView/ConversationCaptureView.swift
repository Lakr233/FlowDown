//
//  ConversationCaptureView.swift
//  FlowDown
//
//  Created by 秋星桥 on 3/19/25.
//

import GlyphixTextFx
import Litext
import SnapKit
import Storage
import UIKit

class ConversationCaptureView: UIView {
    enum LayoutPreset: CGFloat, CaseIterable {
        case small = 350
        case medium = 750
        case large = 1500

        var displayName: String {
            let base = switch self {
            case .small:
                String(localized: "Small")
            case .medium:
                String(localized: "Medium")
            case .large:
                String(localized: "Large")
            }
            return "\(base) (\(Int(rawValue))pt)"
        }
    }

    let session: ConversationSession
    let preset: LayoutPreset
    let layoutWidth: CGFloat

    let titleBar = ChatView.TitleBar()
    let listView = MessageListView()
    let sepB = SeparatorView()
    let avatarView = UIImageView()

    let appLabel = UILabel()
    private var listHeightConstraint: Constraint?

    init(session: ConversationSession, preset: LayoutPreset) {
        self.session = session
        self.preset = preset
        layoutWidth = preset.rawValue

        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        titleBar.textLabel.textColor = .label
        titleBar.setDecorativeBackgroundHidden(true)
        titleBar.icon.alpha = 1
        titleBar.overrideUserInterfaceStyle = .light
        titleBar.use(identifier: session.id)
        addSubview(titleBar)
        titleBar.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
        }

        listView.session = session
        listView.overrideUserInterfaceStyle = .light
        listView.backgroundColor = .white
        addSubview(listView)
        listView.snp.makeConstraints { make in
            make.top.equalTo(titleBar.snp.bottom).offset(16 - 4)
            make.width.equalTo(layoutWidth)
            make.left.right.equalToSuperview()
            listHeightConstraint = make.height.equalTo(5000).priority(.required).constraint
        }

        addSubview(sepB)
        sepB.overrideUserInterfaceStyle = .light
        sepB.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(listView.snp.bottom)
            make.height.equalTo(1)
        }

        avatarView.image = .avatar
        avatarView.contentMode = .scaleAspectFit
        avatarView.layerCornerRadius = 6
        avatarView.layer.cornerCurve = .continuous
        avatarView.overrideUserInterfaceStyle = .light
        addSubview(avatarView)
        avatarView.snp.makeConstraints { make in
            make.width.height.equalTo(24)
            make.top.equalTo(sepB.snp.bottom).offset(16)
            make.centerX.equalToSuperview()
        }

        appLabel.font = UIFont.rounded(ofSize: 12).bold
        appLabel.textColor = .label
        appLabel.text = "FlowDown.AI"
        appLabel.textAlignment = .center
        appLabel.overrideUserInterfaceStyle = .light
        addSubview(appLabel)
        appLabel.snp.makeConstraints { make in
            make.top.equalTo(avatarView.snp.bottom).offset(8)
            make.bottom.equalToSuperview().offset(-16)
            make.left.right.equalToSuperview()
        }

        clipsToBounds = true
        isUserInteractionEnabled = false
        overrideUserInterfaceStyle = .light
        backgroundColor = .white
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
    }

    func capture(controller: UIViewController, _ completion: @escaping (UIImage?) -> Void) {
        assert(Thread.isMainThread)

        controller.view.addSubview(self)
        snp.remakeConstraints { make in
            make.top.equalTo(controller.view.snp.top)
            make.left.equalTo(controller.view.snp.right)
            make.width.equalTo(layoutWidth).priority(.required)
            make.height.equalTo(5000).priority(.required)
        }
        controller.view.layoutIfNeeded()
        layoutIfNeeded()

        forceLightAppearanceRefresh()
        listView.updateList()

        waitForStableLayout { [weak self, weak controller] stableListHeight in
            guard let self, let controller else {
                completion(nil)
                return
            }

            setNeedsLayout()
            layoutIfNeeded()
            listHeightConstraint?.update(offset: stableListHeight)
            layoutIfNeeded()

            let finalHeight = calculateRenderedHeight(listHeight: stableListHeight)

            snp.updateConstraints { make in
                make.height.equalTo(finalHeight).priority(.required)
            }

            controller.view.layoutIfNeeded()
            layoutIfNeeded()

            Task { @MainActor in
                try await Task.sleep(for: .seconds(1))
                let finalSize = CGSize(width: self.layoutWidth, height: finalHeight)
                let format = UIGraphicsImageRendererFormat.default()
                format.scale = UIScreen.main.scale
                format.opaque = true
                let renderer = UIGraphicsImageRenderer(size: finalSize, format: format)
                let image = renderer.image { context in
                    context.cgContext.setFillColor(UIColor.white.cgColor)
                    context.cgContext.fill(CGRect(origin: .zero, size: finalSize))
                    self.layer.render(in: context.cgContext)
                }
                completion(image)
                try await Task.sleep(for: .seconds(1))
                self.removeFromSuperview()
            }
        }
    }
}

private extension ConversationCaptureView {
    func forceLightAppearanceRefresh() {
        var queue: [UIView] = [self]
        while let view = queue.first {
            queue.removeFirst()
            queue.append(contentsOf: view.subviews)
            if let label = view as? GlyphixTextLabel {
                label.textColor = .label
            } else if let titleLabel = view as? UILabel {
                titleLabel.textColor = titleLabel.textColor.resolvedColor(with: traitCollection)
            }
        }
    }

    func waitForStableLayout(maxIterations: Int = 20, completion: @escaping (CGFloat) -> Void) {
        var previousHeight: CGFloat = -1
        var iteration = 0
        var latestHeight: CGFloat = 0

        func evaluate() {
            guard iteration <= maxIterations else {
                completion(max(latestHeight, 0))
                return
            }

            iteration += 1
            setNeedsLayout()
            layoutIfNeeded()
            listView.layoutIfNeeded()

            let contentHeight = max(listView.contentSize.height, 0)
            listHeightConstraint?.update(offset: contentHeight)
            latestHeight = contentHeight
            layoutIfNeeded()

            if abs(contentHeight - previousHeight) < 0.5, previousHeight >= 0 {
                completion(contentHeight)
                return
            }

            previousHeight = contentHeight
            Task { @MainActor in
                try await Task.sleep(for: .milliseconds(100))
                evaluate()
            }
        }

        Task { @MainActor in evaluate() }
    }

    func calculateRenderedHeight(listHeight: CGFloat) -> CGFloat {
        titleBar.layoutIfNeeded()
        appLabel.layoutIfNeeded()

        let titleHeight = titleBar.systemLayoutSizeFitting(
            .init(width: layoutWidth, height: UIView.layoutFittingCompressedSize.height),
        ).height
        let labelHeight = appLabel.systemLayoutSizeFitting(
            .init(width: layoutWidth, height: UIView.layoutFittingCompressedSize.height),
        ).height

        let topSpacing: CGFloat = 16 - 4
        let separatorHeight: CGFloat = 1
        let spacingBelowSeparator: CGFloat = 16
        let avatarHeight: CGFloat = 24
        let spacingAvatarToLabel: CGFloat = 8
        let bottomPadding: CGFloat = 16

        let total = titleHeight
            + topSpacing
            + listHeight
            + separatorHeight
            + spacingBelowSeparator
            + avatarHeight
            + spacingAvatarToLabel
            + labelHeight
            + bottomPadding

        return max(1, ceil(total))
    }
}

//
//  Created by ktiays on 2025/2/7.
//  Copyright (c) 2025 ktiays. All rights reserved.
//

import ListViewKit
import Litext
import MarkdownView
import UIKit

class MessageListRowView: ListRowView, UIContextMenuInteractionDelegate {
    var theme: MarkdownTheme = .default {
        didSet {
            themeDidUpdate()
            setNeedsLayout()
        }
    }

    let contentView = UIView()
    var contextMenuProvider: ((CGPoint) -> UIMenu?)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = false // tool tip will extend out
        addSubview(contentView)
        contentView.isUserInteractionEnabled = true

        contentView.addInteraction(UIContextMenuInteraction(delegate: self))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        themeDidUpdate()
        super.layoutSubviews()

        let insets = MessageListView.listRowInsets
        contentView.frame = CGRect(
            x: insets.left,
            y: 0,
            width: bounds.width - insets.horizontal,
            height: bounds.height - insets.bottom,
        )
    }

    /// A right click belongs to the row's context menu unless it lands on a text
    /// selection. Selectable labels otherwise take it: they select the word under
    /// the pointer and open the system text menu, which hides Retry, Copy and the
    /// rest of the row's actions.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let view = super.hitTest(point, with: event)
        guard event?.buttonMask == .secondary,
              let view,
              let label = enclosingTextLabel(of: view),
              !label.selectionContains(point, from: self)
        else { return view }
        return contentView
    }

    private func enclosingTextLabel(of view: UIView) -> TextLabelView? {
        var current: UIView? = view
        while let candidate = current, candidate !== self {
            if let label = candidate as? TextLabelView { return label }
            current = candidate.superview
        }
        return nil
    }

    func themeDidUpdate() {}

    override func prepareForReuse() {
        super.prepareForReuse()
        contextMenuProvider = nil

        // clear any TextLabelView selection
        var queue = subviews
        while let v = queue.first {
            queue.removeFirst()
            queue.append(contentsOf: v.subviews)
            (v as? TextLabelView)?.clearSelection()
        }
    }

    // MARK: - UIContextMenuInteractionDelegate

    func contextMenuInteraction(
        _: UIContextMenuInteraction,
        configurationForMenuAtLocation location: CGPoint,
    ) -> UIContextMenuConfiguration? {
        guard let menu = contextMenuProvider?(location) else { return nil }
        return .init {
            guard let snapshot = self.contentView.snapshotView(afterScreenUpdates: false) else {
                return nil
            }

            let controller = UIViewController()
            controller.preferredContentSize = self.contentView.bounds.size + CGSize(width: 16, height: 16)
            controller.view.backgroundColor = .systemBackground
            controller.view.addSubview(snapshot)
            snapshot.snp.makeConstraints { make in
                make.edges.equalToSuperview().inset(8)
            }
            return controller
        } actionProvider: { _ in
            menu
        }
    }
}

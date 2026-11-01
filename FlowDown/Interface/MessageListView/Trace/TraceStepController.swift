//
//  TraceStepController.swift
//  FlowDown
//

import Litext
import UIKit

/// One step of the trace, opened from its row: a thought's whole text or a
/// call's arguments by name and its result (`TraceBody`), as plain
/// selectable text. A step still streaming grows here as it comes, below
/// wherever the reader is.
final class TraceStepController: UIViewController {
    let stepID: String
    private let scrollView = UIScrollView()
    private let body = TextLabelView()
    /// What the body shows, nil when it shows nothing.
    private var key: TraceBody.Key?
    /// Between the text and the page's top and foot.
    private static let padding: CGFloat = 16

    init(stepID: String, body key: TraceBody.Key?, title: String) {
        self.stepID = stepID
        super.init(nibName: nil, bundle: nil)
        self.title = title
        body.isSelectable = true
        body.isAccessibilityElement = true
        body.accessibilityTraits = .staticText
        body.delegate = self
        show(key)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(stepID:body:title:)")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        scrollView.alwaysBounceVertical = true
        scrollView.addSubview(body)
        view.addSubview(scrollView)
        setContentScrollView(scrollView)
    }

    /// A step that did not change keeps the reader's selection.
    func show(_ key: TraceBody.Key?) {
        var key = key
        key?.size = UIApplication.shared.preferredContentSizeCategory
        guard key != self.key else { return }
        self.key = key
        body.clearSelection()
        body.attributedText = key.map(TraceBody.text) ?? NSAttributedString()
        body.accessibilityLabel = body.attributedText.string
        viewIfLoaded?.setNeedsLayout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // the text is set in the size it was built for
        guard let key, key.size != UIApplication.shared.preferredContentSizeCategory else { return }
        show(key)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        scrollView.frame = view.bounds
        let readable = view.readableContentGuide.layoutFrame
        guard readable.width > 0 else { return }
        // measured once for each text and width (`TraceBody`)
        let height = key.map { TraceBody.height(for: $0, width: readable.width) } ?? 0
        body.frame = CGRect(x: readable.minX, y: Self.padding, width: readable.width, height: height)
        scrollView.contentSize = CGSize(width: view.bounds.width, height: height + Self.padding * 2)
    }
}

extension TraceStepController: TextLabelViewDelegate {
    func textLabelView(
        _ label: TextLabelView,
        editMenuForSelection selection: NSRange,
        suggestedActions: [UIMenuElement],
    ) -> UIMenu? {
        ChatSelectionMenu.menu(for: label, selection: selection, suggestedActions: suggestedActions)
    }
}

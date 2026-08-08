//
//  MainController+SidbarDragger.swift
//  FlowDown
//
//  Created by 秋星桥 on 7/2/25.
//

import Combine
import SnapKit
import UIKit

class SidebarDraggerView: UIView {
    let allowedMinimalValue = 200
    let initialValue = 256
    let allowedMaximalValue = 512

    /// Width of the invisible strip that accepts pointer input.
    ///
    /// The visible handle is much thinner than this. The strip is what makes
    /// the separator comfortable to grab with a mouse, where the pointer has to
    /// land on an exact pixel instead of a fingertip sized area.
    static let interactiveWidth: CGFloat = 16

    /// Distance the pointer has to travel before a collapsed sidebar comes back.
    private let expandThreshold: CGFloat = 24

    @Published var currentValue: Int {
        didSet {
            if currentValue < allowedMinimalValue { currentValue = allowedMinimalValue }
            if currentValue > allowedMaximalValue { currentValue = allowedMaximalValue }
            UserDefaults.standard.set(currentValue, forKey: "SidebarWidth")
        }
    }

    /// Called when the drag went far enough to the left to hide the sidebar.
    /// Returns whether the sidebar actually collapsed.
    var onSuggestCollapse: (() -> Bool) = { false }

    /// Called when the collapsed dragger is pulled or clicked to bring the
    /// sidebar back. Returns whether the sidebar actually expanded.
    var onSuggestExpand: (() -> Bool) = { false }

    /// Whether the sidebar this dragger controls is currently hidden.
    ///
    /// While collapsed the dragger parks at the leading edge of the window and
    /// works as a handle that restores the sidebar, so the drag that hides the
    /// sidebar always has a matching gesture to undo it.
    var isCollapsed: Bool = false {
        didSet {
            guard oldValue != isCollapsed else { return }
            hideDragger()
        }
    }

    let handlerView = UIView().with {
        $0.backgroundColor = .label.withAlphaComponent(0.5)
        $0.clipsToBounds = true
        $0.layer.cornerRadius = 2
        $0.layer.cornerCurve = .continuous
        $0.alpha = 0
    }

    init() {
        currentValue = UserDefaults.standard.integer(forKey: "SidebarWidth")
        super.init(frame: .zero)
        backgroundColor = .background.withAlphaComponent(0.001)

        if currentValue < allowedMinimalValue { currentValue = allowedMinimalValue }
        if currentValue > allowedMaximalValue { currentValue = allowedMaximalValue }

        addSubview(handlerView)
        handlerView.snp.makeConstraints { make in
            make.width.equalTo(4)
            make.height.equalToSuperview()
            make.center.equalToSuperview()
        }

        isUserInteractionEnabled = true

        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        addGestureRecognizer(hover)

        let dragGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDrag(_:)))
        dragGesture.minimumNumberOfTouches = 1
        dragGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(dragGesture)

        let click = UITapGestureRecognizer(target: self, action: #selector(handleClick(_:)))
        click.numberOfTapsRequired = 1
        addGestureRecognizer(click)

        let doubleClickReset = UITapGestureRecognizer(target: self, action: #selector(handleDoubleClickReset(_:)))
        doubleClickReset.numberOfTapsRequired = 2
        addGestureRecognizer(doubleClickReset)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    @objc private func handleHover(_ gesture: UIHoverGestureRecognizer) {
        switch gesture.state {
        case .began, .changed: showDragger()
        default:
            // The pointer routinely leaves the strip while resizing, the handle
            // has to stay put until the drag itself ends.
            guard !isDragging else { return }
            hideDragger()
        }
    }

    private var isHandlerVisible: Bool = false

    func showDragger() {
        guard !isHandlerVisible else { return }
        isHandlerVisible = true
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.handlerView.alpha = 1
        }
    }

    func hideDragger() {
        guard isHandlerVisible else { return }
        isHandlerVisible = false
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseInOut, .beginFromCurrentState]) {
            self.handlerView.alpha = 0
        }
    }

    private var gestureBeginValue: Int = 0
    private var gestureBeginLocation: CGFloat = 0
    private var lastExpandRequest: Date = .distantPast

    /// Coordinate space the drag is measured in.
    ///
    /// It has to be a view that stays put while the sidebar resizes. Measuring
    /// against the dragger itself feeds each width change back into the next
    /// sample, so the separator oscillates around the pointer instead of
    /// following it.
    private var dragReferenceSpace: UIView { superview ?? self }

    /// Whether a resize is happening right now.
    ///
    /// It keeps the handle visible after the pointer wanders off the strip, and
    /// tells the owner that the width is being driven continuously rather than
    /// changed in one step.
    private(set) var isDragging: Bool = false

    @objc func handleDrag(_ gesture: UIPanGestureRecognizer) {
        let location = gesture.location(in: dragReferenceSpace).x
        switch gesture.state {
        case .began:
            gestureBeginValue = currentValue
            gestureBeginLocation = location
            isDragging = true
            fallthrough
        case .changed:
            showDragger()
            let offset = location - gestureBeginLocation
            if isCollapsed {
                guard offset > expandThreshold else { return }
                if requestExpand() { endDrag(gesture) }
                return
            }
            var decisionValue = gestureBeginValue + Int(offset)
            if decisionValue < allowedMinimalValue {
                if decisionValue < allowedMinimalValue / 2 {
                    if onSuggestCollapse() {
                        endDrag(gesture)
                        return
                    }
                }
                decisionValue = allowedMinimalValue
            }
            if decisionValue > allowedMaximalValue {
                decisionValue = allowedMaximalValue
            }
            currentValue = decisionValue
        default:
            isDragging = false
            hideDragger()
        }
    }

    /// Ends the gesture in place after the sidebar changed state, so the
    /// remaining pointer movement does not keep driving the old interaction.
    private func endDrag(_ gesture: UIPanGestureRecognizer) {
        isDragging = false
        gesture.isEnabled = false
        gesture.isEnabled = true
        hideDragger()
    }

    private func requestExpand() -> Bool {
        guard onSuggestExpand() else { return false }
        lastExpandRequest = .init()
        return true
    }

    @objc func handleClick(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended, isCollapsed else { return }
        _ = requestExpand()
    }

    @objc func handleDoubleClickReset(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        // The first click of this double click may have just restored the
        // sidebar. Resetting the width on top of that is not what was asked.
        guard Date().timeIntervalSince(lastExpandRequest) > 0.5 else { return }
        if isCollapsed {
            _ = requestExpand()
            return
        }
        currentValue = initialValue
    }
}

//
//  MainController+Gesture.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/20/25.
//

import UIKit

extension MainController {
    func updateGestureStatus(withOffset offset: CGFloat) -> Bool {
        updateLayoutGuide(withOffset: offset)
        if isSidebarCollapsed {
            if offset > 100 {
                view.doWithAnimation { self.isSidebarCollapsed = false }
                return true
            }
        } else {
            if offset < -100 {
                view.doWithAnimation { self.isSidebarCollapsed = true }
                return true
            }
        }
        return false
    }

    func updateLayoutGuideToOriginalStatus() {
        updateLayoutGuide(withOffset: 0)
    }

    @objc func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard isSidebarCollapsed else { return }
        let translation = gesture.translation(in: view)
        let velocity = gesture.velocity(in: view)
        let progress = max(0, min(translation.x / 100, 1.0))

        switch gesture.state {
        case .began, .changed:
            updateLayoutGuide(withOffset: max(0, translation.x))
        case .ended:
            if progress > 0.5 || velocity.x > 300 {
                view.doWithAnimation { self.isSidebarCollapsed = false }
            } else {
                updateLayoutGuideToOriginalStatus()
            }
        case .cancelled, .failed:
            updateLayoutGuideToOriginalStatus()
        default:
            break
        }
    }

    private func updateLayoutGuide(withOffset offset: CGFloat) {
        #if targetEnvironment(macCatalyst)
            return
        #else
            var offset = offset
            view.doWithAnimation { [self] in
                if isSidebarCollapsed {
                    gestureLayoutGuide.snp.updateConstraints { make in
                        make.width.equalTo(max(0, offset))
                    }
                } else {
                    if offset > 0 { offset *= 0.1 }
                    gestureLayoutGuide.snp.updateConstraints { make in
                        make.left.equalTo(sidebarLayoutView.snp.right).offset(offset)
                    }
                }
            }
        #endif
    }
}

//
//  MainController+Fold.swift
//  FlowDown
//
//  Created by FlowDown on 2026/10/17.
//

import UIKit

extension MainController {
    /// Gap the relaxed layout keeps around the sidebar: between the window's
    /// leading safe edge and the sidebar, and between the sidebar and the chat.
    static let relaxedLayoutSpacing: CGFloat = 20

    /// Narrowest chat the layout leaves room for next to the sidebar.
    static let minimumChatWidth: CGFloat = 300

    /// Where the sidebar and the chat meet while a fold runs down the window.
    struct SidebarFoldSplit: Equatable {
        /// Sidebar width that ends the sidebar and its gutter at the fold.
        let sidebarWidth: CGFloat
        /// Distance from the sidebar's trailing edge to the chat, which starts
        /// past the fold.
        let chatSpacing: CGFloat
    }

    /// The split that puts the sidebar before a fold and the chat after it.
    ///
    /// The sidebar keeps its leading inset and its gutter, so the sidebar pane
    /// ends at `fold.minX` and the chat starts at `fold.maxX`. A fold that would
    /// need a width outside `minimumWidth...maximumWidth` gives `nil`, and the
    /// layout keeps the width the user chose: clamping it there would leave the
    /// chat across the fold anyway.
    static func sidebarSplit(
        fold: CGRect,
        sidebarMinX: CGFloat,
        minimumWidth: CGFloat,
        maximumWidth: CGFloat,
    ) -> SidebarFoldSplit? {
        let width = fold.minX - relaxedLayoutSpacing - sidebarMinX
        guard width >= minimumWidth, width <= maximumWidth else { return nil }
        return .init(
            sidebarWidth: width,
            chatSpacing: fold.maxX - (sidebarMinX + width),
        )
    }

    /// The split for the fold currently running down this window, if any.
    func sidebarSplitAtFold() -> SidebarFoldSplit? {
        guard let fold = activeVerticalDivision() else { return nil }
        return Self.sidebarSplit(
            fold: fold,
            sidebarMinX: view.safeAreaInsets.left + Self.relaxedLayoutSpacing,
            minimumWidth: CGFloat(sidebarDragger.allowedMinimalValue),
            maximumWidth: min(
                CGFloat(sidebarDragger.allowedMaximalValue),
                view.bounds.width - Self.minimumChatWidth,
            ),
        )
    }

    /// Lays the panes out again when the fold appeared, moved or went away
    /// since the last layout, for when the regions update after the hinge
    /// handler already ran.
    func relayoutIfFoldMoved() {
        guard currentSidebarPresentation == .persistent else { return }
        guard sidebarSplitAtFold() != appliedSidebarFoldSplit else { return }
        scheduleSidebarLayout()
    }

    /// The fold of a partly opened iPhone Duo when it runs down this window,
    /// in the coordinates of `view`.
    private func activeVerticalDivision() -> CGRect? {
        #if FLOWDOWN_HAS_RESERVED_REGIONS && !targetEnvironment(macCatalyst)
            // Regions describe the window's display; a view being removed
            // from it (folding closed) has none to ask about.
            if #available(iOS 27.1, *), view.window != nil {
                let content = view.bounds
                for region in view.reservedRegions(kind: .division) {
                    let regionFrame: CGRect = region.frame
                    // Compared by edges: a fold reported as a zero-width
                    // line is an empty rect, which `intersects` rejects.
                    guard region.isActive,
                          regionFrame.height >= regionFrame.width,
                          regionFrame.maxY > content.minY,
                          regionFrame.minY < content.maxY,
                          regionFrame.minX > content.minX,
                          regionFrame.maxX < content.maxX
                    else { continue }
                    return regionFrame
                }
            }
        #endif
        return nil
    }

    /// Lays the panes out again when the device folds or unfolds.
    func installFoldObserver() {
        #if FLOWDOWN_HAS_RESERVED_REGIONS && !targetEnvironment(macCatalyst)
            if #available(iOS 27.1, *) {
                // Half open and flat open have the same bounds, so a fold
                // change alone would not lay the panes out again.
                //
                // The handler's isolation is not documented, and it also
                // runs when the view leaves the window (folding closed). So it
                // asserts nothing about its thread and only schedules a layout
                // on the main actor, which is skipped once off screen.
                let interaction = UIHingeInteraction { @Sendable [weak self] _, _ in
                    Task { @MainActor [weak self] in
                        guard let self, view.window != nil else { return }
                        scheduleSidebarLayout()
                    }
                }
                view.addInteraction(interaction)
            }
        #endif
    }
}

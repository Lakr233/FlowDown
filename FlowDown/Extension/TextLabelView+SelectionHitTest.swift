//
//  TextLabelView+SelectionHitTest.swift
//  FlowDown
//

import Litext
import UIKit

extension TextLabelView {
    /// Whether `point`, in `view`'s coordinates, lands on the selection this
    /// label takes part in.
    ///
    /// The cells of a Markdown table share one `TextSelectionGroup`, so the
    /// part of the selection under the point can sit in another cell, and
    /// clearing any member clears the whole group.
    func selectionContains(_ point: CGPoint, from view: UIView) -> Bool {
        let holders = selectionGroup?.selectedSegments.map(\.label) ?? [self]
        return holders.contains { label in
            label.selectionContains(label.convert(point, from: view))
        }
    }
}

import UIKit

// Message rows lay their frames out left to right and pass them through
// here: left to right a frame comes back as it went in, right to left it is
// mirrored across the span it was laid out in, so leading and trailing swap
// sides as the system's own views do.

extension CGRect {
    /// This rect mirrored across the vertical centre line of `span`.
    func mirrored(across span: CGRect) -> CGRect {
        var rect = self
        rect.origin.x = span.minX + span.maxX - maxX
        return rect
    }
}

extension UIView {
    /// Whether this view lays out right to left. Not SwifterSwift's
    /// `isRightToLeft`, which would make the name ambiguous.
    var laysOutRightToLeft: Bool {
        effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// `frame`, worked out left to right across `span` (these bounds unless
    /// given), for one of this view's subviews in this view's direction.
    func directionalFrame(_ frame: CGRect, across span: CGRect? = nil) -> CGRect {
        laysOutRightToLeft ? frame.mirrored(across: span ?? bounds) : frame
    }
}

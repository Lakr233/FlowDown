//
//  ModalWindowSize.swift
//  FlowDown
//

import UIKit

/// Size for sheet-style windows (settings, code viewer) on top of the main
/// window.
///
/// Sheets follow the main window at 80% of its size, clamped by a minimum
/// that keeps their content usable and a maximum that keeps them from
/// spanning wall-sized displays edge to edge. A window too small for the
/// minimum gets the largest sheet that still fits it.
enum ModalWindowSize {
    static let minimum = CGSize(width: 720, height: 640)
    static let maximum = CGSize(width: 1200, height: 800)
    static let fractionOfWindow: CGFloat = 0.8

    static func resolve(in window: UIWindow?) -> CGSize {
        guard let bounds = window?.bounds.size else { return minimum }
        let width = min(max(bounds.width * fractionOfWindow, minimum.width), maximum.width)
        let height = min(max(bounds.height * fractionOfWindow, minimum.height), maximum.height)
        // The holder pins its content to these constants; keep them inside
        // what the window can actually host so the two never fight.
        return CGSize(
            width: min(width, max(bounds.width - 32, 0)),
            height: min(height, max(bounds.height - 32, 0))
        )
    }

    static var keyWindow: UIWindow? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
        return windows.first(where: \.isKeyWindow) ?? windows.first
    }
}

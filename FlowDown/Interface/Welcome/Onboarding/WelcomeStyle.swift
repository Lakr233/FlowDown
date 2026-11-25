// Copyright (c) 2026 OwnGoal Studio. MIT; see LICENSE beside this file.
// Ported from Apelin (Interface/Onboarding/WelcomeStyle.swift, itself copied
// from Irisin). Only the accent differs: FlowDown's own `.accent`.
//
//  WelcomeStyle.swift
//  FlowDown
//

import UIKit

/// The welcome typography and system colors shared by every onboarding page.
enum WelcomeStyle {
    static var accent: UIColor {
        .accent
    }

    /// The title on the filled button, whose ground is `accent`.
    static var accentForeground: UIColor {
        .white
    }

    static let horizontalMargin: CGFloat = 24

    /// The ground of every page after the first: light grouped background,
    /// and a near-black #111111 in dark mode.
    static var groupedBackground: UIColor {
        UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0x11 / 255, green: 0x11 / 255, blue: 0x11 / 255, alpha: 1)
                : .systemGroupedBackground
        }
    }

    /// The fixed, bold, two-line heading of the welcome page.
    static var titleFont: UIFont {
        .systemFont(ofSize: 32, weight: .bold)
    }

    /// The system body style used for introductions and page text.
    static var subtitleFont: UIFont {
        .preferredFont(forTextStyle: .body)
    }

    /// The system footnote style used under titles and below lists.
    static var detailFont: UIFont {
        .preferredFont(forTextStyle: .footnote)
    }

    /// The system headline assigned before the filled button configuration.
    static var buttonFont: UIFont {
        .preferredFont(forTextStyle: .headline)
    }

    /// The sheet ground of the welcome page.
    static var background: UIColor {
        .systemBackground
    }

    /// Primary system label text.
    static var titleColor: UIColor {
        .label
    }

    /// Secondary system label text.
    static var detailColor: UIColor {
        .secondaryLabel
    }
}

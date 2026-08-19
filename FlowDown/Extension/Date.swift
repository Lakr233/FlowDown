//
//  Date.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/19/26.
//

import Foundation

private let promptTimestampFormatter = DateFormatter().with {
    // Locale-independent so the year and timezone survive every localization,
    // minute precision keeps the prompt stable across a session.
    $0.locale = Locale(identifier: "en_US_POSIX")
    $0.dateFormat = "yyyy-MM-dd HH:mm EEEE 'GMT'xxx"
}

extension Date {
    /// Timestamp for model prompts, eg: `2026-08-19 12:35 Wednesday GMT+08:00`.
    var promptTimestamp: String {
        promptTimestampFormatter.string(from: self)
    }
}

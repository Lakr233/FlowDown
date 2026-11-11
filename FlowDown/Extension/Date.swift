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

    /// Day-precision date for per-request model context, eg:
    /// `2026-08-19 Wednesday (Asia/Shanghai, GMT+08:00)`. It changes once a
    /// day, so requests within a day stay byte-identical.
    func promptDay(in timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd EEEE"
        let day = formatter.string(from: self)
        formatter.dateFormat = "'GMT'xxx"
        let offset = formatter.string(from: self)
        return "\(day) (\(timeZone.identifier), \(offset))"
    }
}

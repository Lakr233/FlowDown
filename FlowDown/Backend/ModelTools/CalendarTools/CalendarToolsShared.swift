//
//  CalendarToolsShared.swift
//  FlowDown
//
//  Created by 秋星桥 on 8/12/26.
//

import EventKit
import Foundation

enum CalendarToolsShared {
    /// Asks for calendar access using whichever API the running OS provides.
    /// Returns whether it was granted, and the error EventKit gave when the
    /// request itself failed.
    static func requestAccess() async -> (granted: Bool, error: (any Swift.Error)?) {
        let eventStore = EKEventStore()
        do {
            let granted: Bool
            if #available(iOS 17, macCatalyst 17, *) {
                granted = try await eventStore.requestFullAccessToEvents()
            } else {
                granted = try await eventStore.requestAccess(to: .event)
            }
            return (granted, nil)
        } catch {
            return (false, error)
        }
    }
}

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
    /// Both calendar tools used to inline this `#available` dance themselves.
    static func requestAccess(completion: @escaping (Bool, (any Swift.Error)?) -> Void) {
        let eventStore = EKEventStore()
        if #available(iOS 17, macCatalyst 17, *) {
            eventStore.requestFullAccessToEvents { granted, error in completion(granted, error) }
        } else {
            eventStore.requestAccess(to: .event) { granted, error in completion(granted, error) }
        }
    }
}

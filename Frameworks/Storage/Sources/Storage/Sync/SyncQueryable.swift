//
//  SyncQueryable.swift
//  Storage
//
//  Created by king on 2025/10/13.
//

import Foundation
import WCDBSwift

package struct SyncQueryProperties {
    let objectId: WCDBSwift.Property
    let creation: WCDBSwift.Property
    let modified: WCDBSwift.Property
    let removed: WCDBSwift.Property
}

package protocol SyncQueryable {
    static var SyncQuery: SyncQueryProperties { get }
}

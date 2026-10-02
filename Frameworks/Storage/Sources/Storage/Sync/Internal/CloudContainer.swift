//
//  CloudContainer.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

@available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
package protocol CloudContainer<Database>: AnyObject, Equatable, Hashable, Sendable {
    associatedtype Database: CloudDatabase

    func accountStatus() async throws -> CKAccountStatus
    var containerIdentifier: String? { get }
    var privateCloudDatabase: Database { get }

    static func createContainer(identifier containerIdentifier: String) -> Self
}

@available(iOS 15, tvOS 15, macOS 12, watchOS 8, *)
extension CKContainer: CloudContainer {
    package static func createContainer(identifier containerIdentifier: String) -> Self {
        Self(identifier: containerIdentifier)
    }
}

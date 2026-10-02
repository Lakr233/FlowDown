//
//  MockCloudContainer.swift
//  Storage
//
//  Created by king on 2025/10/15.
//

import CloudKit

package final class MockCloudContainer: CloudContainer {
    package static let mockCloudContainers = LockIsolated<[String: MockCloudContainer]>([:])

    package let _accountStatus: LockIsolated<CKAccountStatus>
    package let containerIdentifier: String?
    package let privateCloudDatabase: MockCloudDatabase

    package init(
        accountStatus: CKAccountStatus = .available,
        containerIdentifier: String?,
        privateCloudDatabase: MockCloudDatabase,
    ) {
        _accountStatus = LockIsolated(accountStatus)
        self.containerIdentifier = containerIdentifier
        self.privateCloudDatabase = privateCloudDatabase

        guard let containerIdentifier else { return }
        MockCloudContainer.mockCloudContainers.withValue {
            $0[containerIdentifier] = self
        }
    }

    package func accountStatus() async throws -> CKAccountStatus {
        _accountStatus.withValue { $0 }
    }

    package static func createContainer(identifier containerIdentifier: String)
        -> MockCloudContainer
    {
        MockCloudContainer.mockCloudContainers.withValue { storage in
            let container: MockCloudContainer
            if let existingContainer = storage[containerIdentifier] {
                return existingContainer
            } else {
                container = MockCloudContainer(
                    accountStatus: .available,
                    containerIdentifier: containerIdentifier,
                    privateCloudDatabase: MockCloudDatabase(
                        databaseScope: .private,
                        dataManager: MockDataManager(
                            temporaryDirectory: FileManager.default.temporaryDirectory
                                .appending(component: UUID().uuidString)
                        )
                    ),
                )
                container.privateCloudDatabase.set(container: container)
            }
            storage[containerIdentifier] = container
            return container
        }
    }

    package static func == (lhs: MockCloudContainer, rhs: MockCloudContainer) -> Bool {
        lhs === rhs
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }
}

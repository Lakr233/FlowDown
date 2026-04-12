//
//  AppEnvironment.swift
//  FlowDown
//
//  Created by OpenAI Code Assistant on 2/17/25.
//

import Foundation
import Storage

/// Centralizes core services so they can be swapped (for previews/tests) without touching global singletons.
nonisolated enum AppEnvironment {
    nonisolated struct Container {
        nonisolated let storage: Storage
        nonisolated let syncEngine: SyncEngine
    }

    private static var containerStack: [Container] = []

    nonisolated static var isBootstrapped: Bool {
        !containerStack.isEmpty
    }

    nonisolated static var current: Container {
        guard let container = containerStack.last else {
            fatalError("Call AppEnvironment.bootstrap(_) before accessing dependencies.")
        }
        return container
    }

    @discardableResult
    nonisolated static func bootstrap(_ container: Container) -> Container {
        containerStack = [container]
        apply(container)
        return container
    }

    nonisolated static func push(_ container: Container) {
        containerStack.append(container)
        apply(container)
    }

    nonisolated static func pop() {
        guard containerStack.count > 1 else {
            assertionFailure("Attempted to pop the root AppEnvironment container.")
            return
        }
        _ = containerStack.popLast()
        if let container = containerStack.last {
            apply(container)
        }
    }

    private nonisolated static func apply(_ container: Container) {
        Storage.setSyncEngine(container.syncEngine)
    }
}

nonisolated extension AppEnvironment.Container {
    nonisolated static func live() throws -> AppEnvironment.Container {
        let storage = try Storage.db()
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let shouldUseMockSync = isRunningTests

        let shouldEnableCloudSync = SyncEngine.isCloudSyncSupported
        if !shouldEnableCloudSync || shouldUseMockSync {
            SyncEngine.setSyncEnabled(false)
        }

        let mode: SyncEngine.Mode = shouldUseMockSync ? .mock : .live
        let automaticallySync = shouldUseMockSync ? false : shouldEnableCloudSync

        #if DEBUG
            let infoDic = Bundle.main.infoDictionary
            let value = infoDic?["UIApplicationSupportsMultipleScenes"] as? Bool
            assert(value == false)
        #endif

        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: mode,
            automaticallySync: automaticallySync,
        )
        return .init(storage: storage, syncEngine: syncEngine)
    }
}

/// Convenience accessors to keep existing call sites small.
nonisolated var sdb: Storage {
    AppEnvironment.current.storage
}

nonisolated var syncEngine: SyncEngine {
    AppEnvironment.current.syncEngine
}

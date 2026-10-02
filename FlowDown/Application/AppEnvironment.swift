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

    private static var container: Container?

    nonisolated static var isBootstrapped: Bool {
        container != nil
    }

    nonisolated static var current: Container {
        guard let container else {
            fatalError("Call AppEnvironment.bootstrap(_) before accessing dependencies.")
        }
        return container
    }

    nonisolated static func bootstrap(_ newValue: Container) {
        container = newValue
        Storage.setSyncEngine(newValue.syncEngine)
    }
}

nonisolated extension AppEnvironment.Container {
    nonisolated static func live() throws -> AppEnvironment.Container {
        let storage = try Storage.db()
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        let shouldEnableCloudSync = SyncEngine.isCloudSyncSupported(
            containerIdentifier: CloudKitConfig.containerIdentifier
        )
        let shouldUseMockSync = isRunningTests || !shouldEnableCloudSync
        if shouldUseMockSync {
            SyncEngine.setSyncEnabled(false)
        }

        let mode: SyncEngine.Mode = shouldUseMockSync ? .mock : .live

        #if DEBUG
            let infoDic = Bundle.main.infoDictionary
            let value = infoDic?["UIApplicationSupportsMultipleScenes"] as? Bool
            assert(value == false)
        #endif

        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: mode,
            automaticallySync: !shouldUseMockSync,
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

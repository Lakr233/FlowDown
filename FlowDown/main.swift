//
//  main.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import ConfigurableKit
@_exported import Foundation
@_exported import Logger
import MLX
@_exported import SnapKit
import Storage
@_exported import SwifterSwift
@_exported import UIKit

let logger = Logger.app
_ = LogStore.shared

let disposableResourcesDir = FileManager.default
    .temporaryDirectory
    .appendingPathComponent("DisposableResources")

private func boot() throws -> Never {
    #if !targetEnvironment(simulator)
        do {
            // make sure sandbox is enabled otherwise panic the app
            let sandboxTestDir = URL(fileURLWithPath: "/tmp/sandbox.test.\(UUID().uuidString)")
            FileManager.default.createFile(atPath: sandboxTestDir.path, contents: nil, attributes: nil)
            if FileManager.default.fileExists(atPath: sandboxTestDir.path) {
                fatalError("this app should not run outside of sandbox which may cause trouble.")
            }
        }
    #endif

    let environment = try AppEnvironment.Container.live()
    AppEnvironment.bootstrap(environment)

    #if DEBUG
        logger.infoFile("running in DEBUG mode")
        ConfigurableKit.storage = UserDefaultKeyValueStorage(suite: .standard, prefix: "in-house.")
    #endif

    #if targetEnvironment(simulator) || arch(x86_64)
        ConfigurableKit.set(value: false, forKey: MLX.GPU.isSupportedKey)
        assert(!MLX.GPU.isSupported)
    #else
        ConfigurableKit.set(value: true, forKey: MLX.GPU.isSupportedKey)
        assert(MLX.GPU.isSupported)
    #endif

    _ = ModelManager.shared
    _ = ModelToolsManager.shared
    _ = ConversationManager.shared
    _ = MCPService.shared

    Task.detached(priority: .background) {
        try? FileManager.default.removeItem(at: disposableResourcesDir)
    }

    #if targetEnvironment(macCatalyst)
        _ = UpdateManager.shared
        FLDCatalystHelper.shared.install()
    #endif

    _ = ChatSelection.shared

    _ = UIApplicationMain(
        CommandLine.argc,
        CommandLine.unsafeArgv,
        nil,
        NSStringFromClass(AppDelegate.self),
    )

    fatalError("UIApplicationMain returned unexpectedly.")
}

do {
    try boot()
} catch {
    logger.errorFile("startup failed \(error)")
    RecoveryMode.launch(with: error)
}

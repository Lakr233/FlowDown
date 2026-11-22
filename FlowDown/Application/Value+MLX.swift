//
//  Value+MLX.swift
//  FlowDown
//
//  Created by 秋星桥 on 1/31/25.
//

import ChatClientKit
import ConfigurableKit
import Foundation
import MLX
import UIKit

extension MLX.GPU {
    static let isSupportedKey = "Device.isMlxSupported"
    static var isSupported: Bool {
        ConfigurableKit.value(forKey: isSupportedKey) ?? false
    }

    /// The retired "Inference Cache" setting. MLX now always keeps its runtime
    /// resources and gives them back under memory pressure instead.
    static let retiredCacheSizeKey = "wiki.qaq.MLX.GPU.cacheSize"

    private nonisolated(unsafe) static var memoryPressureSource: DispatchSourceMemoryPressure?
    private nonisolated(unsafe) static var memoryWarningObserver: NSObjectProtocol?

    /// Starts watching for memory pressure. MLX keeps its buffer cache and the
    /// loaded model between requests; when the system runs low on memory they
    /// are offloaded through `LocalInferenceQueue`, which waits for a running
    /// generation to finish first.
    static func startMemoryPressureMonitoring() {
        removeRetiredSettings()

        #if targetEnvironment(simulator) || arch(x86_64)
            return
        #else
            assert(Thread.isMainThread)
            guard memoryPressureSource == nil else { return }

            memoryWarningObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil,
                queue: .main,
            ) { _ in
                requestOffload(reason: "memory warning")
            }

            let source = DispatchSource.makeMemoryPressureSource(
                eventMask: [.warning, .critical],
                queue: .main,
            )
            source.setEventHandler { [weak source] in
                guard let event = source?.data else { return }
                requestOffload(reason: event.contains(.critical) ? "critical memory pressure" : "memory pressure warning")
            }
            source.activate()
            memoryPressureSource = source
        #endif
    }

    static func requestOffload(reason: String) {
        guard isSupported else { return }
        Logger.model.infoFile("requesting MLX offload: \(reason)")
        Task { await LocalInferenceQueue.shared.requestOffload() }
    }

    /// Frees the MLX buffer cache and unloads the cached model container.
    /// Only `LocalInferenceQueue` calls this, while no generation runs.
    static func offloadRuntimeResources() async {
        guard isSupported else { return }
        await MLXModelCoordinator.shared.reset()
        MLX.Memory.clearCache()
        Logger.model.infoFile("offloaded MLX runtime resources")
    }

    private static func removeRetiredSettings() {
        guard let storage = ConfigurableKit.storage as? UserDefaultKeyValueStorage else { return }
        storage.setValue(nil, forKey: retiredCacheSizeKey)
    }
}

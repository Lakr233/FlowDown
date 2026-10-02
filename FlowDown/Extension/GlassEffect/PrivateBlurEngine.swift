//
//  PrivateBlurEngine.swift
//  FlowDown
//
//  Created by Codex on 2026/3/16.
//

import UIKit

enum PrivateBlurEngine {
    private final class NullAction: NSObject, CAAction {
        @objc func run(forKey _: String, object _: Any, arguments _: [AnyHashable: Any]?) {}
    }

    private final class SimpleLayerDelegate: NSObject, CALayerDelegate {
        func action(for _: CALayer, forKey _: String) -> CAAction? {
            PrivateBlurEngine.nullAction
        }
    }

    private static let nullAction = NullAction()
    private static let layerDelegate = SimpleLayerDelegate()

    private static let backdropLayerClass: NSObject.Type? = {
        let name = ("CA" as NSString).appendingFormat("BackdropLayer")
        return NSClassFromString(name as String) as? NSObject.Type
    }()

    private static var cachedBackdropAllocMethod: (@convention(c) (AnyObject, Selector) -> NSObject?, Selector)?
    private static var cachedBackdropInitMethod: (@convention(c) (NSObject, Selector) -> NSObject?, Selector)?

    @inline(__always)
    private static func getMethod<T>(object: AnyObject, selector: String) -> T? {
        guard let method = object.method(for: NSSelectorFromString(selector)) else {
            return nil
        }
        return unsafeBitCast(method, to: T.self)
    }

    static func makeBackdropLayer() -> CALayer? {
        guard let backdropLayerClass else {
            return nil
        }

        let allocatedObject: NSObject?
        if let cachedBackdropAllocMethod {
            allocatedObject = cachedBackdropAllocMethod.0(backdropLayerClass, cachedBackdropAllocMethod.1)
        } else {
            let selector = NSSelectorFromString("alloc")
            let method: (@convention(c) (AnyObject, Selector) -> NSObject?)? = getMethod(
                object: backdropLayerClass,
                selector: "alloc",
            )
            guard let method else {
                return nil
            }
            cachedBackdropAllocMethod = (method, selector)
            allocatedObject = method(backdropLayerClass, selector)
        }

        guard let allocatedObject else {
            return nil
        }

        if let cachedBackdropInitMethod {
            return cachedBackdropInitMethod.0(allocatedObject, cachedBackdropInitMethod.1) as? CALayer
        }

        let selector = NSSelectorFromString("init")
        let method: (@convention(c) (NSObject, Selector) -> NSObject?)? = getMethod(
            object: allocatedObject,
            selector: "init",
        )
        guard let method else {
            return nil
        }
        cachedBackdropInitMethod = (method, selector)
        return method(allocatedObject, selector) as? CALayer
    }

    @inline(__always)
    private static func _k(_ encoded: String) -> String {
        guard let d = Data(base64Encoded: encoded),
              let s = String(data: d, encoding: .utf8)
        else { return encoded }
        return s
    }

    static func configureBackdropLayer(_ backdropLayer: CALayer) {
        backdropLayer.delegate = layerDelegate
        backdropLayer.setValue(0.5, forKey: _k("c2NhbGU="))
        backdropLayer.rasterizationScale = 1.0
    }

    private static func makeFilter(type: String) -> NSObject? {
        guard let filterClass = NSClassFromString(_k("Q0FGaWx0ZXI=")) else {
            return nil
        }

        let filterClassObject = filterClass as AnyObject
        let selector = NSSelectorFromString(_k("ZmlsdGVyV2l0aFR5cGU6"))
        guard filterClassObject.responds(to: selector),
              let unmanagedFilter = filterClassObject.perform(selector, with: type)
        else {
            return nil
        }

        return unmanagedFilter.takeUnretainedValue() as? NSObject
    }

    static func makeGaussianBlurFilter(radius: CGFloat) -> NSObject? {
        let blurFilter = makeFilter(type: _k("Z2F1c3NpYW5CbHVy"))
        blurFilter?.setValue(radius as NSNumber, forKey: _k("aW5wdXRSYWRpdXM="))
        return blurFilter
    }
}

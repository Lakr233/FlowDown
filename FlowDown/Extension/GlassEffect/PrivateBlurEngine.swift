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
                selector: "alloc"
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
            selector: "init"
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

    static let maskSourceLayerName = "mask_source"

    static func configureBackdropLayer(_ backdropLayer: CALayer) {
        backdropLayer.delegate = layerDelegate
        backdropLayer.setValue(0.5, forKey: _k("c2NhbGU="))
        backdropLayer.rasterizationScale = 1.0
    }

    private static func makeFilter(type: String) -> NSObject? {
        guard let data = Data(base64Encoded: "Q0FGaWx0ZXI="),
              let filterClassString = String(data: data, encoding: .utf8),
              let filterClass = NSClassFromString(filterClassString) as? NSObjectProtocol
        else {
            return nil
        }

        let selector = NSSelectorFromString(_k("ZmlsdGVyV2l0aFR5cGU6"))
        guard filterClass.responds(to: selector),
              let unmanagedFilter = (filterClass as AnyObject).perform(selector, with: type)
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

    static func makeVariableBlurFilter(
        radius: CGFloat,
        maskImage: CGImage,
        isTransparent: Bool
    ) -> NSObject? {
        guard let variableBlur = makeFilter(type: _k("dmFyaWFibGVCbHVy")) else {
            return nil
        }

        variableBlur.setValue(radius, forKey: _k("aW5wdXRSYWRpdXM="))
        variableBlur.setValue(maskImage, forKey: _k("aW5wdXRNYXNrSW1hZ2U="))
        if isTransparent {
            variableBlur.setValue(true, forKey: _k("aW5wdXROb3JtYWxpemVFZGdlc1RyYW5zcGFyZW50"))
        } else {
            variableBlur.setValue(true, forKey: _k("aW5wdXROb3JtYWxpemVFZGdlcw=="))
        }
        return variableBlur
    }

    static func makeVariableBlurFilter(
        radius: CGFloat,
        sublayerSourceName: String,
        isTransparent: Bool
    ) -> NSObject? {
        guard let variableBlur = makeFilter(type: _k("dmFyaWFibGVCbHVy")) else {
            return nil
        }

        variableBlur.setValue(radius, forKey: _k("aW5wdXRSYWRpdXM="))
        variableBlur.setValue(sublayerSourceName, forKey: _k("aW5wdXRTb3VyY2VTdWJsYXllck5hbWU="))
        if isTransparent {
            variableBlur.setValue(true, forKey: _k("aW5wdXROb3JtYWxpemVFZGdlc1RyYW5zcGFyZW50"))
        } else {
            variableBlur.setValue(true, forKey: _k("aW5wdXROb3JtYWxpemVFZGdlcw=="))
        }
        return variableBlur
    }

    final class MaskedBlurView: UIView {
        private let maxBlurRadius: CGFloat
        private let isTransparent: Bool
        private let backdropLayer: CALayer?
        private let maskSourceView: UIImageView?
        private let usesSublayerSource: Bool

        init(maxBlurRadius: CGFloat = 20, isTransparent: Bool = false) {
            self.maxBlurRadius = maxBlurRadius
            self.isTransparent = isTransparent

            let backdrop = PrivateBlurEngine.makeBackdropLayer()
            self.backdropLayer = backdrop

            if #available(iOS 26.0, macCatalyst 26.0, *) {
                let maskView = UIImageView()
                maskView.contentMode = .scaleToFill
                maskView.layer.name = PrivateBlurEngine.maskSourceLayerName
                self.maskSourceView = maskView
                self.usesSublayerSource = true
            } else {
                self.maskSourceView = nil
                self.usesSublayerSource = false
            }

            super.init(frame: .zero)

            if let backdrop {
                layer.addSublayer(backdrop)
                PrivateBlurEngine.configureBackdropLayer(backdrop)

                if usesSublayerSource, let maskSourceView {
                    backdrop.addSublayer(maskSourceView.layer)
                    if let filter = PrivateBlurEngine.makeVariableBlurFilter(
                        radius: maxBlurRadius,
                        sublayerSourceName: PrivateBlurEngine.maskSourceLayerName,
                        isTransparent: isTransparent
                    ) {
                        backdrop.filters = [filter]
                    }
                }
            }

            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError()
        }

        override func layoutSubviews() {
            super.layoutSubviews()

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdropLayer?.frame = bounds
            maskSourceView?.frame = bounds
            CATransaction.commit()
        }

        func update(size: CGSize, maskImage: UIImage?) {
            guard size.width > 0, size.height > 0 else {
                maskSourceView?.image = nil
                if !usesSublayerSource {
                    backdropLayer?.filters = nil
                }
                return
            }

            let bounds = CGRect(origin: .zero, size: size)

            CATransaction.begin()
            CATransaction.setDisableActions(true)
            backdropLayer?.frame = bounds
            maskSourceView?.frame = bounds
            CATransaction.commit()

            if usesSublayerSource {
                maskSourceView?.image = maskImage
                return
            }

            guard let cgImage = maskImage?.cgImage,
                  let filter = PrivateBlurEngine.makeVariableBlurFilter(
                      radius: maxBlurRadius,
                      maskImage: cgImage,
                      isTransparent: isTransparent
                  )
            else {
                backdropLayer?.filters = nil
                return
            }

            backdropLayer?.filters = [filter]
        }
    }
}

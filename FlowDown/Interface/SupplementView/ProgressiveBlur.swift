//
//  ProgressiveBlur.swift
//
//  Origin: Figson's standalone ProgressiveBlur.swift (AirBuild chat
//  attachment d993aa14, 2026-11-10), copied verbatim; only this origin note
//  is added. The numbers and the math are the owner's — do not tune here.
//
//  PRIVATE API: `CABackdropLayer` and `CAFilter` (variableBlur, gaussianBlur,
//  colorMatrix) are looked up at runtime with NSClassFromString. If either is
//  missing, the layers are simply absent and the edge degrades to nothing
//  rather than crashing. The app already relies on the same classes in
//  `PrivateBlurEngine` / `LegacyGlassBackdropView`.
//
//  Soft scroll edge under a bar, built the way the system builds its own
//  pocket: a light variable blur of the content, a frost of the content
//  over it, both strongest at `edge` and eased (smootherstep) to nothing,
//  so no line marks where it ends.
//
//  Uses private CABackdropLayer / CAFilter. If either is missing the view
//  draws nothing (content is simply not blurred).
//

import SwiftUI
import UIKit

// MARK: - Numbers

struct ProgressiveBlurStyle: Equatable {
    /// Variable blur radius at the edge — light; the frost does the work.
    var radius: CGFloat = 1.1
    /// Fraction of the height, from the edge, held at full strength.
    var hold: CGFloat = 0.1
    /// Frost layer: gaussian blur radius and opacity at the edge
    /// (system pocket is 16 pt / 0.6; this is a third of the opacity).
    var frostRadius: CGFloat = 16
    var frostOpacity: Double = 0.2

    static let standard = Self()

    /// Smootherstep from 1 at `edge` (through `hold`) to 0 at the far end.
    /// `fraction` = 0 at the top, 1 at the bottom.
    func strength(at fraction: CGFloat, edge: VerticalEdge) -> CGFloat {
        let fromFar = edge == .top ? 1 - fraction : fraction
        let t = min(max(fromFar / max(1 - hold, 0.01), 0), 1)
        return t * t * t * (t * (6 * t - 15) + 10)
    }

    /// 1 px wide alpha column, one row per point, for the variable blur.
    func mask(edge: VerticalEdge, height: CGFloat) -> CGImage? {
        let rows = max(2, Int(height.rounded(.up)))
        guard let context = CGContext(
            data: nil, width: 1, height: rows, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue
        ) else { return nil }
        for row in 0 ..< rows {
            // Core Graphics counts rows from the bottom.
            let fraction = CGFloat(rows - 1 - row) / CGFloat(rows - 1)
            context.setFillColor(gray: 0, alpha: strength(at: fraction, edge: edge))
            context.fill(CGRect(x: 0, y: row, width: 1, height: 1))
        }
        return context.makeImage()
    }
}

// MARK: - UIKit view (usable directly from UIKit too)

final class ProgressiveBlurView: UIView {
    var edge: VerticalEdge = .top { didSet { setNeedsLayout() } }
    var style: ProgressiveBlurStyle = .standard { didSet { setNeedsLayout() } }

    /// System soft pocket's colour matrix for its frost.
    private static let frostMatrix: [Float] = [
        0.8688, 0.1191, 0.0121, 0, 0,
        0.0354, 0.9525, 0.0120, 0, 0,
        0.0354, 0.1192, 0.8454, 0, 0,
        0, 0, 0, 1, 0,
    ]
    private static let stopCount = 16

    private let content = ProgressiveBlurView.backdrop()
    private let frost = ProgressiveBlurView.backdrop()
    private let frostMask = CAGradientLayer()
    private var drawn: (edge: VerticalEdge, height: CGFloat, style: ProgressiveBlurStyle)?

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        frost?.mask = frostMask
        for sublayer in [content, frost].compactMap(\.self) {
            layer.addSublayer(sublayer)
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let content, let frost else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let scale = traitCollection.displayScale
        content.setValue(scale, forKey: "scale")
        frost.setValue(scale, forKey: "scale")
        content.frame = bounds
        frost.frame = bounds
        frostMask.frame = bounds

        let height = bounds.height
        guard height > 0,
              drawn.map({ $0.edge != edge || $0.height != height || $0.style != style }) ?? true,
              let mask = style.mask(edge: edge, height: height)
        else { return }
        drawn = (edge, height, style)

        content.filters = [
            Self.filter("variableBlur", [
                "inputRadius": style.radius,
                "inputMaskImage": mask,
                "inputNormalizeEdges": true,
            ]),
        ].compactMap(\.self)

        frost.isHidden = style.frostOpacity <= 0
        frost.filters = [
            Self.filter("gaussianBlur", [
                "inputRadius": style.frostRadius,
                "inputNormalizeEdges": true,
                "inputDither": true,
            ]),
            Self.filter("colorMatrix", [
                "inputColorMatrix": Self.frostMatrix.withUnsafeBytes {
                    NSValue(bytes: $0.baseAddress!, objCType: "{CAColorMatrix=ffffffffffffffffffff}")
                },
            ]),
        ].compactMap(\.self)

        let locations = (0 ... Self.stopCount).map { CGFloat($0) / CGFloat(Self.stopCount) }
        frostMask.locations = locations.map { NSNumber(value: Double($0)) }
        frostMask.colors = locations.map {
            CGColor(gray: 0, alpha: style.frostOpacity * style.strength(at: $0, edge: edge))
        }
    }

    private static func backdrop() -> CALayer? {
        (NSClassFromString("CABackdropLayer") as? CALayer.Type)?.init()
    }

    private static func filter(_ type: String, _ values: [String: Any]) -> NSObject? {
        guard let filterType = NSClassFromString("CAFilter") as? NSObject.Type,
              let filter = filterType
              .perform(NSSelectorFromString("filterWithType:"), with: type)?
              .takeUnretainedValue() as? NSObject
        else { return nil }
        for (key, value) in values {
            filter.setValue(value, forKey: key)
        }
        return filter
    }
}

// MARK: - SwiftUI

struct ProgressiveBlur: UIViewRepresentable {
    var edge: VerticalEdge = .top
    var style: ProgressiveBlurStyle = .standard

    func makeUIView(context _: Context) -> ProgressiveBlurView { ProgressiveBlurView() }

    func updateUIView(_ view: ProgressiveBlurView, context _: Context) {
        view.edge = edge
        view.style = style
    }
}

/// Under the top bar: through the safe area and `reach` past it.
struct TopProgressiveBlur: View {
    var reach: CGFloat = 28
    var style: ProgressiveBlurStyle = .standard

    var body: some View {
        GeometryReader { proxy in
            ProgressiveBlur(edge: .top, style: style)
                .frame(height: proxy.safeAreaInsets.top + reach)
                .ignoresSafeArea(edges: .top)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Over a bottom bar / input area: through the safe area and `reach` above it.
struct BottomProgressiveBlur: View {
    var reach: CGFloat = 28
    var style: ProgressiveBlurStyle = .standard

    var body: some View {
        GeometryReader { proxy in
            ProgressiveBlur(edge: .bottom, style: style)
                .frame(height: proxy.safeAreaInsets.bottom + reach)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Usage
//
// 1. Turn off the system's own top edge, and hide the bar background:
//
//      // SwiftUI scroll view / List
//      .scrollEdgeEffectStyle(nil, for: .top)        // or .scrollEdgeEffectHidden(true, for: .top)
//      .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
//
//      // UIKit scroll view (iOS 26+)
//      scrollView.topEdgeEffect.isHidden = true
//      navigationBar appearance: configureWithTransparentBackground()
//
// 2. Lay the blur over the content, under the header controls:
//
//      content
//          .overlay(alignment: .top) { TopProgressiveBlur(reach: 28) }
//
//    or, when the header is its own overlay, as its background running a
//    tail past its bottom so text behind the title is already unreadable:
//
//      header
//          .padding(.bottom, 14)
//          .background {
//              ProgressiveBlur()
//                  .padding(.bottom, -28)
//                  .ignoresSafeArea(.container, edges: [.top, .horizontal])
//          }
//
//    UIKit: add a ProgressiveBlurView above the scroll view, pinned to the
//    top of the view (not the safe area), height = safeAreaInsets.top + bar
//    height + 28, isUserInteractionEnabled = false.

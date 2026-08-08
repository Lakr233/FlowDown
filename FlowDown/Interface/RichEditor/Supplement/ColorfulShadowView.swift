import ColorfulX
import UIKit

private let idlePalette: [ColorElement] = [
    UIColor(white: 0.0, alpha: 0.10),
]
private let intelligentPalette: [ColorElement] = [
    ColorfulPreset.appleIntelligence.colors,
].flatMap(\.self)

final class ColorfulShadowView: UIView {
    enum Mode: Equatable {
        case idle
        case appleIntelligence
    }

    struct Geometry: Equatable {
        var innerRect: CGRect
        var cornerRadius: CGFloat
        var blur: CGFloat
        var offset: CGSize

        static let zero = Geometry(
            innerRect: .zero,
            cornerRadius: 0,
            blur: 0,
            offset: .zero,
        )
    }

    private let director: SpeckleAnimationRoundedRectangleDirector
    private let gradientView: AnimatedMulticolorGradientView
    private let maskLayer = CALayer()

    var shadowRadius: CGFloat = 1.0 {
        didSet {
            guard shadowRadius != oldValue else { return }
            needsMaskUpdate = true
            setNeedsLayout()
        }
    }

    private var geometry: Geometry = .zero {
        didSet {
            guard geometry != oldValue else { return }
            needsMaskUpdate = true
            setNeedsLayout()
        }
    }

    private var needsMaskUpdate = true
    private var lastBoundsSize: CGSize = .zero
    private var lastMaskRegeneration: CFTimeInterval = 0
    private var hasDeferredMaskUpdate = false

    var mode: Mode = .idle {
        didSet { applyCurrentMode() }
    }

    private var timer: Timer?

    init() {
        director = SpeckleAnimationRoundedRectangleDirector(
            inset: -0.2,
            cornerRadius: 1,
            direction: .clockwise,
            movementRate: 0.05,
            positionResponseRate: 100,
        )
        gradientView = AnimatedMulticolorGradientView(animationDirector: director)

        super.init(frame: .zero)

        isUserInteractionEnabled = false
        gradientView.isUserInteractionEnabled = false
        gradientView.backgroundColor = .clear
        gradientView.transitionSpeed = 16
        gradientView.noise = 0
        gradientView.bias /= 1000
        gradientView.speed = 1
        gradientView.frameLimit = 30
        addSubview(gradientView)
        maskLayer.contentsScale = layer.contentsScale
        gradientView.layer.mask = maskLayer

        applyCurrentMode()

        #if targetEnvironment(macCatalyst)
            // there looks like some black magic on app nap that
            // wont dismiss our colorful effect when text stream ended in background
            // we force update to try to fix this
            let timer = Timer(timeInterval: 3, repeats: true) { [weak self] _ in
                self?.updateContents()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError()
    }

    deinit {
        timer?.invalidate()
        timer = nil
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        gradientView.frame = bounds

        guard needsMaskUpdate || lastBoundsSize != bounds.size else { return }

        // The mask is a full size image rasterised with a shadow blur, which is
        // far too much to redo on every frame of a live resize. The layer keeps
        // stretching the mask it already has - it is a soft glow, so a frame or
        // two of the previous shape is invisible - and the real one is redrawn
        // once the size stops moving.
        maskLayer.frame = bounds
        let now = CACurrentMediaTime()
        guard now - lastMaskRegeneration >= Self.maskRegenerationInterval else {
            scheduleDeferredMaskUpdate()
            return
        }
        lastMaskRegeneration = now
        regenerateMask()
        lastBoundsSize = bounds.size
    }

    /// Shortest gap between two rasterisations while the size keeps changing.
    private static let maskRegenerationInterval: CFTimeInterval = 0.1

    private func scheduleDeferredMaskUpdate() {
        guard !hasDeferredMaskUpdate else { return }
        hasDeferredMaskUpdate = true
        let delay = Self.maskRegenerationInterval - (CACurrentMediaTime() - lastMaskRegeneration)
        DispatchQueue.main.asyncAfter(deadline: .now() + max(delay, 0.016)) { [weak self] in
            guard let self else { return }
            hasDeferredMaskUpdate = false
            needsMaskUpdate = true
            setNeedsLayout()
        }
    }

    func updateGeometry(_ geometry: Geometry) {
        self.geometry = geometry
    }
}

private extension ColorfulShadowView {
    @objc func updateContents() {
        setNeedsLayout()
        layoutIfNeeded()
        applyCurrentMode()
    }

    func regenerateMask() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        guard geometry.innerRect.width > 0, geometry.innerRect.height > 0 else { return }

        let scale: CGFloat
        #if targetEnvironment(macCatalyst)
            scale = window?.screen.scale ?? UIScreen.main.scale
        #else
            scale = window?.screen.scale ?? UIScreen.main.scale
        #endif

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false

        let shadowPath = UIBezierPath(roundedRect: geometry.innerRect, cornerRadius: geometry.cornerRadius)

        let image = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            let cgContext = context.cgContext

            // Draw the shadow/glow area
            cgContext.saveGState()
            cgContext.setShadow(offset: geometry.offset, blur: geometry.blur * shadowRadius, color: UIColor.white.cgColor)
            cgContext.setFillColor(UIColor.white.cgColor)
            cgContext.addPath(shadowPath.cgPath)
            cgContext.fillPath()
            cgContext.restoreGState()

            // Cut out the inner rect to create stroke effect
            cgContext.saveGState()
            cgContext.setBlendMode(.clear)
            cgContext.addPath(shadowPath.cgPath)
            cgContext.fillPath()
            cgContext.restoreGState()
        }

        maskLayer.contentsScale = scale
        maskLayer.frame = bounds
        maskLayer.contents = image.cgImage

        needsMaskUpdate = false
    }

    func applyCurrentMode() {
        cancelScheduledSpeedStop()
        switch mode {
        case .idle:
            shadowRadius = 1.0
            gradientView.setColors(idlePalette, animated: true, repeats: true)
            scheduleSpeedStop()
        case .appleIntelligence:
            shadowRadius = 1.0
            gradientView.setColors(intelligentPalette, animated: true, repeats: true)
            gradientView.speed = 1
        }
    }

    @MainActor
    func cancelScheduledSpeedStop() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(stopAnimation),
            object: nil,
        )
    }

    @MainActor
    @objc func scheduleSpeedStop() {
        assert(Thread.isMainThread)
        cancelScheduledSpeedStop()
        perform(
            #selector(stopAnimation),
            with: nil,
            afterDelay: 2.0,
        )
    }

    @objc private func stopAnimation() {
        gradientView.speed = 0
    }
}

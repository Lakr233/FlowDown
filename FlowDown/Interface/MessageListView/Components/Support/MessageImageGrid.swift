import UIKit

/// Image attachments in one aspect-aware album with 2 pt gutters, on the user
/// bubble's accent ground.
final class MessageImageGrid: UIView {
    typealias Item = MessageListView.Attachments.Item

    var onPreview: ((Item) -> Void)?
    var maximumSize: CGSize = .zero {
        didSet {
            if maximumSize != oldValue {
                setNeedsLayout()
            }
        }
    }

    /// The screen's, as the row was measured with (`size(for:…)`).
    var displayScale: CGFloat = 0 {
        didSet {
            if displayScale != oldValue {
                setNeedsLayout()
            }
        }
    }

    private var items: [Item] = []
    private var tiles: [UIButton] = []
    private var aspectRatios: [CGFloat] = []
    private var pixelSizes: [CGSize?] = []
    private let background = MessageAccentGradientView()
    private let content = UIView()
    private static let contentInset: CGFloat = 1
    private static let cornerRadius: CGFloat = 12
    /// The widest an album is drawn.
    private static let maximumWidth: CGFloat = 540

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerCurve = .continuous
        clipsToBounds = true
        addSubview(background)
        content.layer.cornerCurve = .continuous
        content.clipsToBounds = true
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("Use init(frame:)")
    }

    func show(_ images: [Item]) {
        guard images.map(\.id) != items.map(\.id) else { return }
        items = images
        tiles.forEach { $0.removeFromSuperview() }
        tiles = []
        aspectRatios = []
        pixelSizes = []
        let previews = MessageAttachmentPreviews.shared
        for item in images {
            let image = previews.image(for: item)
            aspectRatios.append(image.map { $0.size.width / max($0.size.height, 1) } ?? 1)
            pixelSizes.append(previews.pixelSize(for: item))
            let tile = UIButton(type: .custom)
            let imageView = UIImageView(image: image)
            imageView.contentMode = .scaleAspectFill
            imageView.clipsToBounds = true
            imageView.isUserInteractionEnabled = false
            imageView.frame = tile.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            tile.addSubview(imageView)
            tile.accessibilityLabel = item.name
            tile.addAction(UIAction { [weak self] _ in self?.onPreview?(item) }, for: .touchUpInside)
            content.addSubview(tile)
            tiles.append(tile)
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // an album as small as an icon is rounded as one
        let radius = min(Self.cornerRadius, min(bounds.width, bounds.height) / 4)
        layer.cornerRadius = radius
        content.layer.cornerRadius = max(0, radius - Self.contentInset)
        background.frame = bounds
        content.frame = CGRect(
            x: Self.contentInset,
            y: Self.contentInset,
            width: max(0, bounds.width - Self.contentInset * 2),
            height: max(0, bounds.height - Self.contentInset * 2),
        )
        let frames = Self.contentFrames(
            aspectRatios: aspectRatios,
            pixelSizes: pixelSizes,
            displayScale: displayScale,
            width: maximumSize.width,
            maximumHeight: maximumSize.height,
        )
        // the album reads from the leading edge: right to left, its first
        // image on the right
        for (tile, frame) in zip(tiles, frames) {
            tile.frame = content.directionalFrame(frame)
        }
    }

    /// `displayScale` is the screen's, which makes an image's pixels its own
    /// size in points: one of its pixels to each of the screen's.
    static func size(
        for images: [Item],
        width: CGFloat,
        maximumHeight: CGFloat,
        displayScale: CGFloat,
    ) -> CGSize {
        let previews = MessageAttachmentPreviews.shared
        let ratios = images.map { item -> CGFloat in
            guard let image = previews.image(for: item) else { return 1 }
            return image.size.width / max(image.size.height, 1)
        }
        let frames = contentFrames(
            aspectRatios: ratios,
            pixelSizes: images.map { previews.pixelSize(for: $0) },
            displayScale: displayScale,
            width: width,
            maximumHeight: maximumHeight,
        )
        guard !frames.isEmpty else { return .zero }
        return CGSize(
            width: (frames.map(\.maxX).max() ?? 0) + contentInset * 2,
            height: (frames.map(\.maxY).max() ?? 0) + contentInset * 2,
        )
    }

    private static func contentFrames(
        aspectRatios: [CGFloat],
        pixelSizes: [CGSize?],
        displayScale: CGFloat,
        width: CGFloat,
        maximumHeight: CGFloat,
    ) -> [CGRect] {
        MessageImageLayout.frames(
            aspectRatios: aspectRatios,
            // with no scale yet, the album is as large as the limits
            naturalSizes: pixelSizes.map { pixels in
                guard let pixels, displayScale > 0 else { return nil }
                return CGSize(width: pixels.width / displayScale, height: pixels.height / displayScale)
            },
            width: max(0, min(maximumWidth, width) - contentInset * 2),
            maximumHeight: max(0, maximumHeight - contentInset * 2),
        )
    }
}

import ImageIO
import UIKit

/// Presentation thumbnails for message attachments, decoded once and kept
/// apart from the attachment itself, which stays as it was stored for
/// sending, persistence and preview.
@MainActor
final class MessageAttachmentPreviews {
    typealias Item = MessageListView.Attachments.Item

    static let shared = MessageAttachmentPreviews()

    private final class Result: NSObject {
        let image: UIImage?
        /// The original's pixels, upright, when ImageIO read it: the
        /// thumbnail is never larger than 1080 pixels a side.
        let pixelSize: CGSize?

        init(_ image: UIImage?, pixelSize: CGSize? = nil) {
            self.image = image
            self.pixelSize = pixelSize
        }
    }

    private let cache = NSCache<NSUUID, Result>()

    private init() {
        cache.countLimit = 128
        cache.totalCostLimit = 32 * 1024 * 1024
    }

    /// The thumbnail of an image attachment; nil for text and audio.
    func image(for item: Item) -> UIImage? {
        result(for: item).image
    }

    /// The original image's size in pixels, upright, when known.
    func pixelSize(for item: Item) -> CGSize? {
        result(for: item).pixelSize
    }

    private func result(for item: Item) -> Result {
        if let result = cache.object(forKey: item.id as NSUUID) {
            return result
        }
        let result = Self.decode(item)
        let cost = result.image?.cgImage.map { $0.bytesPerRow * $0.height } ?? 1
        cache.setObject(result, forKey: item.id as NSUUID, cost: cost)
        return result
    }

    private static func decode(_ item: Item) -> Result {
        guard item.type == .image else { return Result(nil) }
        for data in [item.imageRepresentation, item.previewImage] where !data.isEmpty {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                      kCGImageSourceCreateThumbnailFromImageAlways: true,
                      kCGImageSourceThumbnailMaxPixelSize: 1080,
                      kCGImageSourceCreateThumbnailWithTransform: true,
                  ] as CFDictionary)
            else { continue }
            return Result(UIImage(cgImage: thumbnail), pixelSize: uprightPixelSize(source))
        }
        return Result(nil)
    }

    private static func uprightPixelSize(_ source: CGImageSource) -> CGSize? {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
              width > 0, height > 0
        else { return nil }
        // EXIF orientations 5 to 8 turn the picture a quarter
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return (5 ... 8).contains(orientation)
            ? CGSize(width: height, height: width)
            : CGSize(width: width, height: height)
    }
}

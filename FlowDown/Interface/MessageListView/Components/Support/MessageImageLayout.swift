import CoreGraphics
import Foundation

/// Aspect-aware album rows. Keep input order and use small, uniform gutters.
enum MessageImageLayout {
    static let spacing: CGFloat = 2
    /// The least a tile is drawn at, however few pixels its image has.
    static let minimumSide: CGFloat = 32

    /// The album `frames(aspectRatios:width:maximumHeight:)` lays out, made
    /// no larger than its images: shrunk until the image it enlarges least
    /// is drawn at `naturalSizes`, its own size in points, but never below
    /// `minimumSide` on a tile's shorter side, nor above the limits. An
    /// image of unknown size (nil) keeps the album as large as the limits.
    static func frames(
        aspectRatios: [CGFloat],
        naturalSizes: [CGSize?],
        width: CGFloat,
        maximumHeight: CGFloat = .greatestFiniteMagnitude,
    ) -> [CGRect] {
        let full = frames(aspectRatios: aspectRatios, width: width, maximumHeight: maximumHeight)
        guard !full.isEmpty, naturalSizes.count == full.count else { return full }
        var leastEnlargement = CGFloat.infinity
        var shortestSide = CGFloat.infinity
        for (frame, natural) in zip(full, naturalSizes) {
            guard let natural, natural.width.isFinite, natural.height.isFinite,
                  natural.width > 0, natural.height > 0
            else { return full }
            // a tile fills with its image, so the image covers both sides
            leastEnlargement = min(leastEnlargement, max(frame.width / natural.width, frame.height / natural.height))
            shortestSide = min(shortestSide, frame.width, frame.height)
        }
        var scale = min(1, 1 / leastEnlargement)
        if scale * shortestSide < minimumSide {
            scale = min(1, minimumSide / shortestSide)
        }
        guard scale < 1 else { return full }
        // Laid out again at the smaller width. The gutters stay as wide, so
        // the tiles shrink a little more than the album does: it is widened
        // until its shortest side is back at the minimum (a side grows at
        // least as fast as the album, so one step reaches it), never past
        // the album the limits allow.
        let fullWidth = full.map(\.maxX).max() ?? 0
        var albumWidth = fullWidth * scale
        var fitted = frames(aspectRatios: aspectRatios, width: albumWidth, maximumHeight: maximumHeight)
        for _ in 0 ..< 3 {
            let shortest = fitted.map { min($0.width, $0.height) }.min() ?? 0
            guard shortest > 0, shortest < minimumSide - 0.001, albumWidth < fullWidth else { break }
            albumWidth = min(fullWidth, albumWidth * minimumSide / shortest)
            fitted = frames(aspectRatios: aspectRatios, width: albumWidth, maximumHeight: maximumHeight)
        }
        return fitted
    }

    static func frames(
        aspectRatios: [CGFloat],
        width: CGFloat,
        maximumHeight: CGFloat = .greatestFiniteMagnitude,
    ) -> [CGRect] {
        guard maximumHeight > 0 else { return [] }
        let frames = naturalFrames(aspectRatios: aspectRatios, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        guard height > maximumHeight else { return frames }
        let scale = maximumHeight / height
        return frames.map { $0.applying(CGAffineTransform(scaleX: scale, y: scale)) }
    }

    private static func naturalFrames(aspectRatios: [CGFloat], width: CGFloat) -> [CGRect] {
        guard !aspectRatios.isEmpty, width.isFinite, width > 0 else { return [] }
        let spacing = min(Self.spacing, width / CGFloat(aspectRatios.count + 1))
        let ratios = aspectRatios.map { $0.isFinite && $0 > 0 ? min(100, max(0.01, $0)) : 1 }
        if ratios.count == 1 {
            let height = min(width / ratios[0], 540)
            return [CGRect(x: 0, y: 0, width: min(width, height * ratios[0]), height: height)]
        }
        if ratios.count == 3, ratios[0] < 0.8 {
            let height = min(width * 1.1, 540)
            let left = (width - spacing) * 0.56
            let right = width - left - spacing
            let top = (height - spacing) * ratios[2] / (ratios[1] + ratios[2])
            return [CGRect(x: 0, y: 0, width: left, height: height),
                    CGRect(x: left + spacing, y: 0, width: right, height: top),
                    CGRect(x: left + spacing, y: top + spacing, width: right, height: height - top - spacing)]
        }

        let cropped = ratios.map { min(2, max(0.5, $0)) }
        let rows: [Int]
        if ratios.count == 2, ratios.allSatisfy({ $0 > 1.4 }) {
            rows = [1, 1]
        } else if (3 ... 4).contains(ratios.count), ratios[0] > 1.2 {
            rows = [1, ratios.count - 1]
        } else {
            // Choose rows nearest half the album's width in height. A lone
            // tile is penalized so a last image does not become a giant row.
            var costs = Array(repeating: CGFloat.infinity, count: cropped.count + 1)
            var counts = Array(repeating: 0, count: cropped.count)
            costs[cropped.count] = 0
            for start in cropped.indices.reversed() {
                for count in 1 ... min(3, cropped.count - start) {
                    let sum = cropped[start ..< (start + count)].reduce(0, +)
                    let height = (width - spacing * CGFloat(count - 1)) / sum
                    let deviation = height / width - 0.5
                    let cost = deviation * deviation + (count == 1 ? 0.8 : 0) + costs[start + count]
                    if cost < costs[start] {
                        costs[start] = cost; counts[start] = count
                    }
                }
            }
            var result: [Int] = []
            var start = 0
            while start < cropped.count {
                result.append(counts[start])
                start += counts[start]
            }
            rows = result
        }

        var frames: [CGRect] = []
        var index = 0
        var y: CGFloat = 0
        for count in rows {
            let sum = cropped[index ..< (index + count)].reduce(0, +)
            let height = (width - spacing * CGFloat(count - 1)) / sum
            var x: CGFloat = 0
            for column in 0 ..< count {
                let tileWidth = column == count - 1 ? width - x : cropped[index] * height
                frames.append(CGRect(x: x, y: y, width: tileWidth, height: height))
                x += tileWidth + spacing
                index += 1
            }
            y += height + spacing
        }
        return frames
    }
}

//
//  ImageAttachmentPreviewTests.swift
//  FlowDownUnitTests
//

@testable import FlowDown
import Foundation
import ImageIO
import Testing
import UIKit

@MainActor
struct ImageAttachmentPreviewTests {
    @Test(arguments: [
        // a photo, a tall screenshot at 3x, and a picture already under the limit
        (CGSize(width: 4000, height: 3000), CGFloat(1), CGSize(width: 480, height: 360)),
        (CGSize(width: 400, height: 800), CGFloat(3), CGSize(width: 240, height: 480)),
        (CGSize(width: 200, height: 100), CGFloat(1), CGSize(width: 200, height: 100)),
    ])
    func imageAttachment_previewStaysWithinThePixelLimit(
        sample: (size: CGSize, scale: CGFloat, previewPixelSize: CGSize),
    ) throws {
        let image = makeImage(size: sample.size, scale: sample.scale)
        let storage = TemporaryStorage(id: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: storage.storageDir) }

        let attachment = try #require(RichEditorView.Object.Attachment(image: image, storage: storage))

        #expect(pixelSize(of: attachment.previewImage) == sample.previewPixelSize)
        // the picture sent to the model is not the preview
        let picture = try #require(image.prepareAttachment())
        #expect(pixelSize(of: attachment.imageRepresentation) == pixelSize(of: picture))
        #expect(try Data(contentsOf: storage.absoluteURL(attachment.storageSuffix)) == attachment.imageRepresentation)
    }
}

private extension ImageAttachmentPreviewTests {
    func makeImage(size: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        }
    }

    func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber
        else { return nil }
        return CGSize(width: width.doubleValue, height: height.doubleValue)
    }
}

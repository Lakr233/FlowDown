//
//  Ext+UIImage.swift
//  RichEditor
//
//  Created by 秋星桥 on 1/17/25.
//

import UIKit

extension UIImage {
    func prepareAttachment() -> Data? {
        if !EditorBehavior.compressImage {
            return jpeg(.highest)?.byRemovingEXIF()
        }

        var image = self

        // resize image if it's too large
        if image.size.width > 1024 || image.size.height > 1024 {
            if let scaled = image.resize(
                withSize: CGSize(width: 1024, height: 1024),
                contentMode: .contentAspectFit,
            ) { image = scaled }
        }

        // we already resized the image, so medium quality is enough
        return image
            .jpeg(.medium)?
            .byRemovingEXIF()
    }
}

extension UIImage {
    enum JPEGQuality: CGFloat {
        case lowest = 0
        case low = 0.25
        case medium = 0.5
        case high = 0.75
        case highest = 1
    }

    /// Returns the data for the specified image in JPEG format.
    /// If the image object’s underlying image data has been purged, calling this function forces that data to be reloaded into memory.
    /// - returns: A data object containing the JPEG data, or nil if there was a problem generating the data. This function may return nil if the image has no data or if the underlying CGImageRef contains data in an unsupported bitmap format.
    func jpeg(_ jpegQuality: JPEGQuality) -> Data? {
        jpegData(compressionQuality: jpegQuality.rawValue)
    }
}

extension UIImage {
    enum ContentMode {
        case contentFill
        case contentAspectFill
        case contentAspectFit
    }

    func resize(withSize size: CGSize, contentMode: ContentMode = .contentAspectFill) -> UIImage? {
        let aspectWidth = size.width / self.size.width
        let aspectHeight = size.height / self.size.height

        switch contentMode {
        case .contentFill:
            return resize(withSize: size)
        case .contentAspectFit:
            let aspectRatio = min(aspectWidth, aspectHeight)
            return resize(
                withSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio)
            )
        case .contentAspectFill:
            let aspectRatio = max(aspectWidth, aspectHeight)
            return resize(
                withSize: CGSize(width: self.size.width * aspectRatio, height: self.size.height * aspectRatio)
            )
        }
    }

    private func resize(withSize size: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        defer { UIGraphicsEndImageContext() }
        draw(in: CGRect(x: 0.0, y: 0.0, width: size.width, height: size.height))
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

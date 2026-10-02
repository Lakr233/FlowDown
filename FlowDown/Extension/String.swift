//
//  String.swift
//  FlowDown
//
//  Created by 秋星桥 on 2/2/25.
//

import Foundation
import UIKit

extension String {
    var sanitizedFileName: String {
        components(separatedBy: .init(charactersIn: #"/\:?%*|"<>"#)).joined(separator: "_")
    }
}

extension String {
    func textToImage(size: CGFloat = 64) -> UIImage? {
        let nsString = (self as NSString)
        let font = UIFont.systemFont(ofSize: size)
        let stringAttributes = [NSAttributedString.Key.font: font]
        let imageSize = nsString.size(withAttributes: stringAttributes)

        UIGraphicsBeginImageContextWithOptions(imageSize, false, 0)
        UIColor.clear.set()
        UIRectFill(CGRect(origin: CGPoint(), size: imageSize))
        nsString.draw(at: CGPoint.zero, withAttributes: stringAttributes)
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return image ?? UIImage()
    }
}

extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

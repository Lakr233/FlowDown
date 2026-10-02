//
//  UIFont.swift
//  FlowDown
//
//  Created by 秋星桥 on 2024/12/31.
//

import UIKit

extension UIFont {
    class func rounded(ofSize size: CGFloat, weight: UIFont.Weight = .regular) -> UIFont {
        let systemFont = UIFont.systemFont(ofSize: size, weight: weight)
        return if let descriptor = systemFont.fontDescriptor.withDesign(.rounded) {
            UIFont(descriptor: descriptor, size: size)
        } else {
            systemFont
        }
    }
}

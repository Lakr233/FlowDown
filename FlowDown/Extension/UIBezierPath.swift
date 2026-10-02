//
//  UIBezierPath.swift
//  ContinuousCorners
//
//  Created by Noah Hilt on 9/26/18.
//  Copyright © 2018 Melted. All rights reserved.
//
//  Based on: https://github.com/everdrone/react-native-super-ellipse-mask

import UIKit

extension UIBezierPath {
    private static let ellipseCoefficient: CGFloat = 1.28195

    static func continuousRoundedRect(_ rect: CGRect, cornerRadius: CGFloat) -> UIBezierPath {
        continuousRoundedRect(rect, cornerRadius: (cornerRadius, cornerRadius, cornerRadius, cornerRadius))
    }

    static func continuousRoundedRect(
        _ rect: CGRect,
        cornerRadius: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat)
    ) -> UIBezierPath {
        let cornerRadius = minimumCornerRadius(for: rect, cornerRadius: cornerRadius)

        let coefficients: [CGFloat] = [
            0.04641, 0.08715, 0.13357, 0.16296, 0.21505, 0.290086, 0.32461, 0.37801, 0.44576, 0.6074, 0.77037
        ]
        let path = UIBezierPath()

        let topRightP1 = CGPoint(x: rect.width - cornerRadius.topRight * ellipseCoefficient, y: rect.origin.y)
        let topRightP1CP1 = CGPoint(x: topRightP1.x + cornerRadius.topRight * coefficients[8], y: topRightP1.y)
        let topRightP1CP2 = CGPoint(
            x: topRightP1.x + cornerRadius.topRight * coefficients[9],
            y: topRightP1.y + cornerRadius.topRight * coefficients[0]
        )

        let topRightP2 = CGPoint(
            x: topRightP1.x + cornerRadius.topRight * coefficients[10],
            y: topRightP1.y + cornerRadius.topRight * coefficients[2]
        )
        let topRightP2CP1 = CGPoint(
            x: topRightP2.x + cornerRadius.topRight * coefficients[3],
            y: topRightP2.y + cornerRadius.topRight * coefficients[1]
        )
        let topRightP2CP2 = CGPoint(
            x: topRightP2.x + cornerRadius.topRight * coefficients[5],
            y: topRightP2.y + cornerRadius.topRight * coefficients[4]
        )

        let topRightP3 = CGPoint(
            x: topRightP2.x + cornerRadius.topRight * coefficients[7],
            y: topRightP2.y + cornerRadius.topRight * coefficients[7]
        )
        let topRightP3CP1 = CGPoint(
            x: topRightP3.x + cornerRadius.topRight * coefficients[1],
            y: topRightP3.y + cornerRadius.topRight * coefficients[3]
        )
        let topRightP3CP2 = CGPoint(
            x: topRightP3.x + cornerRadius.topRight * coefficients[2],
            y: topRightP3.y + cornerRadius.topRight * coefficients[6]
        )

        let topRightP4 = CGPoint(
            x: topRightP3.x + cornerRadius.topRight * coefficients[2],
            y: topRightP3.y + cornerRadius.topRight * coefficients[10]
        )

        let bottomRightP1 = CGPoint(x: rect.width, y: rect.height - cornerRadius.bottomRight * ellipseCoefficient)
        let bottomRightP1CP1 = CGPoint(
            x: bottomRightP1.x,
            y: bottomRightP1.y + cornerRadius.bottomRight * coefficients[8]
        )
        let bottomRightP1CP2 = CGPoint(
            x: bottomRightP1.x - cornerRadius.bottomRight * coefficients[0],
            y: bottomRightP1.y + cornerRadius.bottomRight * coefficients[9]
        )

        let bottomRightP2 = CGPoint(
            x: bottomRightP1.x - cornerRadius.bottomRight * coefficients[2],
            y: bottomRightP1.y + cornerRadius.bottomRight * coefficients[10]
        )
        let bottomRightP2CP1 = CGPoint(
            x: bottomRightP2.x - cornerRadius.bottomRight * coefficients[1],
            y: bottomRightP2.y + cornerRadius.bottomRight * coefficients[3]
        )
        let bottomRightP2CP2 = CGPoint(
            x: bottomRightP2.x - cornerRadius.bottomRight * coefficients[4],
            y: bottomRightP2.y + cornerRadius.bottomRight * coefficients[5]
        )

        let bottomRightP3 = CGPoint(
            x: bottomRightP2.x - cornerRadius.bottomRight * coefficients[7],
            y: bottomRightP2.y + cornerRadius.bottomRight * coefficients[7]
        )
        let bottomRightP3CP1 = CGPoint(
            x: bottomRightP3.x - cornerRadius.bottomRight * coefficients[3],
            y: bottomRightP3.y + cornerRadius.bottomRight * coefficients[1]
        )
        let bottomRightP3CP2 = CGPoint(
            x: bottomRightP3.x - cornerRadius.bottomRight * coefficients[6],
            y: bottomRightP3.y + cornerRadius.bottomRight * coefficients[2]
        )

        let bottomRightP4 = CGPoint(
            x: bottomRightP3.x - cornerRadius.bottomRight * coefficients[10],
            y: bottomRightP3.y + cornerRadius.bottomRight * coefficients[2]
        )

        let bottomLeftP1 = CGPoint(x: rect.origin.x + cornerRadius.bottomLeft * ellipseCoefficient, y: rect.height)
        let bottomLeftP1CP1 = CGPoint(x: bottomLeftP1.x - cornerRadius.bottomLeft * coefficients[8], y: bottomLeftP1.y)
        let bottomLeftP1CP2 = CGPoint(
            x: bottomLeftP1.x - cornerRadius.bottomLeft * coefficients[9],
            y: bottomLeftP1.y - cornerRadius.bottomLeft * coefficients[0]
        )

        let bottomLeftP2 = CGPoint(
            x: bottomLeftP1.x - cornerRadius.bottomLeft * coefficients[10],
            y: bottomLeftP1.y - cornerRadius.bottomLeft * coefficients[2]
        )
        let bottomLeftP2CP1 = CGPoint(
            x: bottomLeftP2.x - cornerRadius.bottomLeft * coefficients[3],
            y: bottomLeftP2.y - cornerRadius.bottomLeft * coefficients[1]
        )
        let bottomLeftP2CP2 = CGPoint(
            x: bottomLeftP2.x - cornerRadius.bottomLeft * coefficients[5],
            y: bottomLeftP2.y - cornerRadius.bottomLeft * coefficients[4]
        )

        let bottomLeftP3 = CGPoint(
            x: bottomLeftP2.x - cornerRadius.bottomLeft * coefficients[7],
            y: bottomLeftP2.y - cornerRadius.bottomLeft * coefficients[7]
        )
        let bottomLeftP3CP1 = CGPoint(
            x: bottomLeftP3.x - cornerRadius.bottomLeft * coefficients[1],
            y: bottomLeftP3.y - cornerRadius.bottomLeft * coefficients[3]
        )
        let bottomLeftP3CP2 = CGPoint(
            x: bottomLeftP3.x - cornerRadius.bottomLeft * coefficients[2],
            y: bottomLeftP3.y - cornerRadius.bottomLeft * coefficients[6]
        )

        let bottomLeftP4 = CGPoint(
            x: bottomLeftP3.x - cornerRadius.bottomLeft * coefficients[2],
            y: bottomLeftP3.y - cornerRadius.bottomLeft * coefficients[10]
        )

        let topLeftP1 = CGPoint(x: rect.origin.x, y: rect.origin.y + cornerRadius.topLeft * ellipseCoefficient)
        let topLeftP1CP1 = CGPoint(x: topLeftP1.x, y: topLeftP1.y - cornerRadius.topLeft * coefficients[8])
        let topLeftP1CP2 = CGPoint(
            x: topLeftP1.x + cornerRadius.topLeft * coefficients[0],
            y: topLeftP1.y - cornerRadius.topLeft * coefficients[9]
        )

        let topLeftP2 = CGPoint(
            x: topLeftP1.x + cornerRadius.topLeft * coefficients[2],
            y: topLeftP1.y - cornerRadius.topLeft * coefficients[10]
        )
        let topLeftP2CP1 = CGPoint(
            x: topLeftP2.x + cornerRadius.topLeft * coefficients[1],
            y: topLeftP2.y - cornerRadius.topLeft * coefficients[3]
        )
        let topLeftP2CP2 = CGPoint(
            x: topLeftP2.x + cornerRadius.topLeft * coefficients[4],
            y: topLeftP2.y - cornerRadius.topLeft * coefficients[5]
        )

        let topLeftP3 = CGPoint(
            x: topLeftP2.x + cornerRadius.topLeft * coefficients[7],
            y: topLeftP2.y - cornerRadius.topLeft * coefficients[7]
        )
        let topLeftP3CP1 = CGPoint(
            x: topLeftP3.x + cornerRadius.topLeft * coefficients[3],
            y: topLeftP3.y - cornerRadius.topLeft * coefficients[1]
        )
        let topLeftP3CP2 = CGPoint(
            x: topLeftP3.x + cornerRadius.topLeft * coefficients[6],
            y: topLeftP3.y - cornerRadius.topLeft * coefficients[2]
        )

        let topLeftP4 = CGPoint(
            x: topLeftP3.x + cornerRadius.topLeft * coefficients[10],
            y: topLeftP3.y - cornerRadius.topLeft * coefficients[2]
        )

        path.move(to: CGPoint(x: rect.origin.x + cornerRadius.topLeft * ellipseCoefficient, y: rect.origin.y))

        // Top right
        path.addLine(to: topRightP1)
        path.addCurve(to: topRightP2, controlPoint1: topRightP1CP1, controlPoint2: topRightP1CP2)
        path.addCurve(to: topRightP3, controlPoint1: topRightP2CP1, controlPoint2: topRightP2CP2)
        path.addCurve(to: topRightP4, controlPoint1: topRightP3CP1, controlPoint2: topRightP3CP2)

        // Bottom right
        path.addLine(to: bottomRightP1)
        path.addCurve(to: bottomRightP2, controlPoint1: bottomRightP1CP1, controlPoint2: bottomRightP1CP2)
        path.addCurve(to: bottomRightP3, controlPoint1: bottomRightP2CP1, controlPoint2: bottomRightP2CP2)
        path.addCurve(to: bottomRightP4, controlPoint1: bottomRightP3CP1, controlPoint2: bottomRightP3CP2)

        // Bottom left
        path.addLine(to: bottomLeftP1)
        path.addCurve(to: bottomLeftP2, controlPoint1: bottomLeftP1CP1, controlPoint2: bottomLeftP1CP2)
        path.addCurve(to: bottomLeftP3, controlPoint1: bottomLeftP2CP1, controlPoint2: bottomLeftP2CP2)
        path.addCurve(to: bottomLeftP4, controlPoint1: bottomLeftP3CP1, controlPoint2: bottomLeftP3CP2)

        // Top Left
        path.addLine(to: topLeftP1)
        path.addCurve(to: topLeftP2, controlPoint1: topLeftP1CP1, controlPoint2: topLeftP1CP2)
        path.addCurve(to: topLeftP3, controlPoint1: topLeftP2CP1, controlPoint2: topLeftP2CP2)
        path.addCurve(to: topLeftP4, controlPoint1: topLeftP3CP1, controlPoint2: topLeftP3CP2)

        path.close()

        return path
    }

    private static func minimumCornerRadius(
        for rect: CGRect,
        cornerRadius: (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat)
    ) -> (topLeft: CGFloat, topRight: CGFloat, bottomLeft: CGFloat, bottomRight: CGFloat) {
        let calculateMinimumRadius: (CGFloat, CGFloat, CGFloat) -> CGFloat = { width, height, radius in
            let minSide = min(width, height)
            let minRadius = min(radius * ellipseCoefficient, minSide)

            return minRadius / ellipseCoefficient
        }

        let w = rect.width
        let h = rect.height

        let minimumTopRight = calculateMinimumRadius(w, h, cornerRadius.topRight)
        let minimumBottomRight = calculateMinimumRadius(
            w,
            h - (minimumTopRight * ellipseCoefficient),
            cornerRadius.bottomRight
        )
        let minimumBottomLeft = calculateMinimumRadius(
            w - (minimumBottomRight * ellipseCoefficient),
            h,
            cornerRadius.bottomLeft
        )
        let minimumTopLeft = calculateMinimumRadius(
            w - (minimumTopRight * ellipseCoefficient),
            h - (minimumBottomLeft * ellipseCoefficient),
            cornerRadius.topLeft
        )

        return (minimumTopLeft, minimumTopRight, minimumBottomLeft, minimumBottomRight)
    }
}

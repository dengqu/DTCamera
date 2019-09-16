//
//  CircleLayer.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/29.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class CircleLayer: CALayer {
    
    var strokeColor: UIColor = .white
    var lineWidth: CGFloat = 0
    @objc dynamic var progress: CGFloat = 0
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(strokeColor: UIColor, lineWidth: CGFloat, progress: CGFloat) {
        self.strokeColor = strokeColor
        self.lineWidth = lineWidth
        self.progress = progress
        super.init()
        contentsScale = UIScreen.main.scale
        setNeedsDisplay()
    }
    
    override init(layer: Any) {
        if let other = layer as? CircleLayer {
            strokeColor = other.strokeColor
            lineWidth = other.lineWidth
            progress = other.progress
        }
        super.init(layer: layer)
    }

    override func draw(in ctx: CGContext) {
        let inset = lineWidth / 2
        ctx.setLineWidth(lineWidth)
        ctx.setLineCap(.round)
        ctx.setStrokeColor(strokeColor.cgColor)
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = bounds.width / 2 - inset
        let startAngle: CGFloat = 270.0 / 180.0 * .pi
        let endAngle: CGFloat = (270.0 + 360.0 * progress) / 180.0 * .pi
        ctx.addArc(center: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: false)
        ctx.strokePath()
    }
    
    override class func needsDisplay(forKey key: String) -> Bool {
        if key == "progress" {
            return true
        }
        return super.needsDisplay(forKey: key)
    }
    
}

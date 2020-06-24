//
//  CircleView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/29.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class CircleView: UIView {
    
    var lineWidth: CGFloat = 10 {
        didSet {
            emptyLayer.lineWidth = lineWidth
            progressLayer.lineWidth = lineWidth
        }
    }
    var progressStrokeColor: UIColor = UIColor.white {
        didSet {
            progressLayer.strokeColor = progressStrokeColor
        }
    }
    var emptyStrokeColor: UIColor = UIColor(white: 1, alpha: 0.5) {
        didSet {
            emptyLayer.strokeColor = emptyStrokeColor
        }
    }
    
    private let emptyLayer: CircleLayer
    private let progressLayer: CircleLayer
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        emptyLayer = CircleLayer(strokeColor: emptyStrokeColor, lineWidth: lineWidth, progress: 1)
        progressLayer = CircleLayer(strokeColor: progressStrokeColor, lineWidth: lineWidth, progress: 0)
        
        super.init(frame: frame)
        
        emptyLayer.frame = frame
        progressLayer.frame = frame
        
        layer.addSublayer(emptyLayer)
        layer.addSublayer(progressLayer)
        
        isOpaque = false
    }
    
    func setProgress(_ progress: CGFloat, isAnimating: Bool = false, duration: TimeInterval = 0) {
        if isAnimating {
            let animation = CABasicAnimation(keyPath: "progress")
            animation.fromValue = progressLayer.progress
            animation.toValue = progress
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animation.duration = duration
            progressLayer.add(animation, forKey: animation.keyPath)
        }
        progressLayer.progress = progress
    }
    
}

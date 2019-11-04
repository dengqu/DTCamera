//
//  PhotoEditorMaskView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/23.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class PhotoEditorMaskView: UIView {
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        isUserInteractionEnabled = false
    }
    
    func toggleMask(rect: CGRect?) {
        if let rect = rect {
            if layer.mask == nil {
                backgroundColor = UIColor(white: 0, alpha: 0.8)
                
                let maskLayer = CAShapeLayer()
                maskLayer.fillRule = .evenOdd
                
                let path = UIBezierPath(rect: bounds)
                path.append(UIBezierPath(rect: rect))
                
                maskLayer.path = path.cgPath
                
                layer.mask = maskLayer
            }
        } else {
            if layer.mask != nil {
                backgroundColor = UIColor.clear
                
                layer.mask = nil
            }
        }
    }
    
}

//
//  PhotoEditorFrameView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/14.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

class PhotoEditorFrameView: UIView {
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    init(longSide: CGFloat, shortSide: CGFloat, borderWidth: CGFloat, borderColor: UIColor) {
        super.init(frame: .zero)
        
        let borderView = UIView()
        borderView.layer.borderColor = borderColor.cgColor
        borderView.layer.borderWidth = borderWidth
        let upLeftCornerView = PhotoEditorCornerView(longSide: longSide,
                                                     shortSide: shortSide,
                                                     position: .upLeftCorner)
        upLeftCornerView.fillColor = borderColor
        let upRightCornerView = PhotoEditorCornerView(longSide: longSide,
                                                      shortSide: shortSide,
                                                      position: .upRightCorner)
        upRightCornerView.fillColor = borderColor
        let downRightCornerView = PhotoEditorCornerView(longSide: longSide,
                                                        shortSide: shortSide,
                                                        position: .downRightCorner)
        downRightCornerView.fillColor = borderColor
        let downLeftCornerView = PhotoEditorCornerView(longSide: longSide,
                                                       shortSide: shortSide,
                                                       position: .downLeftCorner)
        downLeftCornerView.fillColor = borderColor

        addSubview(borderView)
        addSubview(upLeftCornerView)
        addSubview(upRightCornerView)
        addSubview(downRightCornerView)
        addSubview(downLeftCornerView)

        let padding = shortSide - borderWidth
        borderView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(padding)
            make.left.equalToSuperview().offset(padding)
            make.right.equalToSuperview().offset(-padding)
            make.bottom.equalToSuperview().offset(-padding)
        }
        upLeftCornerView.snp.makeConstraints { make in
            make.top.equalTo(borderView).offset(-padding)
            make.left.equalTo(borderView).offset(-padding)
            make.size.equalTo(longSide)
        }
        upRightCornerView.snp.makeConstraints { make in
            make.top.equalTo(borderView).offset(-padding)
            make.right.equalTo(borderView).offset(padding)
            make.size.equalTo(longSide)
        }
        downRightCornerView.snp.makeConstraints { make in
            make.bottom.equalTo(borderView).offset(padding)
            make.right.equalTo(borderView).offset(padding)
            make.size.equalTo(longSide)
        }
        downLeftCornerView.snp.makeConstraints { make in
            make.bottom.equalTo(borderView).offset(padding)
            make.left.equalTo(borderView).offset(-padding)
            make.size.equalTo(longSide)
        }
    }
    
}

class PhotoEditorCornerView: UIView {
    
    var fillColor = UIColor.white {
        didSet {
            setNeedsDisplay()
        }
    }

    enum Position {
        case upLeftCorner
        case upRightCorner
        case downRightCorner
        case downLeftCorner
    }
    
    private let longSide: CGFloat
    private let shortSide: CGFloat
    private let position: Position

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(longSide: CGFloat, shortSide: CGFloat, position: Position) {
        self.longSide = longSide
        self.shortSide = shortSide
        self.position = position
        super.init(frame: .zero)
        backgroundColor = .clear
    }
    
    override func draw(_ rect: CGRect) {        
        if let context = UIGraphicsGetCurrentContext() {
            context.setFillColor(fillColor.cgColor)
            
            switch position {
            case .upLeftCorner:
                UIBezierPath(rect: .init(x: 0, y: 0, width: longSide, height: shortSide)).fill()
                UIBezierPath(rect: .init(x: 0, y: 0, width: shortSide, height: longSide)).fill()
            case .upRightCorner:
                UIBezierPath(rect: .init(x: 0, y: 0, width: longSide, height: shortSide)).fill()
                UIBezierPath(rect: .init(x: longSide - shortSide, y: 0,
                                         width: shortSide, height: longSide)).fill()
            case .downRightCorner:
                UIBezierPath(rect: .init(x: longSide - shortSide, y: 0,
                                         width: shortSide, height: longSide)).fill()
                UIBezierPath(rect: .init(x: 0, y: longSide - shortSide,
                                         width: longSide, height: shortSide)).fill()
            case .downLeftCorner:
                UIBezierPath(rect: .init(x: 0, y: longSide - shortSide,
                                         width: longSide, height: shortSide)).fill()
                UIBezierPath(rect: .init(x: 0, y: 0, width: shortSide, height: longSide)).fill()
            }
        }
    }
    
}

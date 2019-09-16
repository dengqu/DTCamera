//
//  GestureResizeView.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/8/14.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit

protocol PhotoEditorResizeViewDelegate: class {
    func resizeView(_ resizeView: PhotoEditorResizeView, didResize cropRect: CGRect)
    func resizeViewThumbOn(_ resizeView: PhotoEditorResizeView)
    func resizeViewThumbOff(_ resizeView: PhotoEditorResizeView)
}

class PhotoEditorResizeView: UIView {
    
    weak var delegate: PhotoEditorResizeViewDelegate?

    private enum ThumbPosition {
        case unknown
        case upLeftCorner
        case upSide
        case upRightCorner
        case rightSide
        case downRightCorner
        case downSide
        case downLeftCorner
        case leftSide
    }
    
    private let maxFrame: CGRect
    private let minSize: CGFloat
    private let frameView: PhotoEditorFrameView
    private let framePadding: CGFloat = 24
    private let frameLongSide: CGFloat = 18
    private let frameShortSide: CGFloat = 3
    private let frameBorderWidth: CGFloat = 1
    private let frameBorderColor: UIColor = .white
    private let thumbSize: CGFloat = 30
    private var thumbPosition: ThumbPosition = .unknown
    
    private var isDebug = false
    private var thumbPositionView: UIView!
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    init(maxFrame: CGRect) {
        self.maxFrame = maxFrame
        minSize = frameLongSide * 3 + framePadding * 2
        frameView = PhotoEditorFrameView(longSide: frameLongSide, shortSide: frameShortSide,
                                         borderWidth: frameBorderWidth, borderColor: frameBorderColor)

        super.init(frame: .zero)

        isUserInteractionEnabled = true
        
        addSubview(frameView)

        frameView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(framePadding)
            make.left.equalToSuperview().offset(framePadding)
            make.right.equalToSuperview().offset(-framePadding)
            make.bottom.equalToSuperview().offset(-framePadding)
        }
        
        if isDebug {
            layer.borderColor = UIColor.green.cgColor
            layer.borderWidth = 1.0
            thumbPositionView = UIView()
            thumbPositionView.backgroundColor = UIColor.red.withAlphaComponent(0.5)
            addSubview(thumbPositionView)
        }
    }
    
    var cropRectMaxFrame: CGRect {
        let inset = framePadding + frameShortSide
        return maxFrame.inset(by: .init(top: inset, left: inset, bottom: inset, right: inset))
    }
    
    var cropRect: CGRect {
        let inset = framePadding + frameShortSide
        return frame.inset(by: .init(top: inset, left: inset, bottom: inset, right: inset))
    }
    
    var cropRectInResizeView: CGRect {
        let inset = frameShortSide
        return frameView.frame.inset(by: .init(top: inset, left: inset, bottom: inset, right: inset))
    }
    
    var maskClipRect: CGRect {
        let inset = -frameBorderWidth / 2.0
        return cropRect.inset(by: .init(top: inset, left: inset, bottom: inset, right: inset))
    }
    
    func updateFrame(wtih cropRect: CGRect) {
        let inset = -framePadding - frameShortSide
        frame = cropRect.inset(by: .init(top: inset, left: inset, bottom: inset, right: inset))
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touchPoint = touches.first?.location(in: self) else { return }
        
        thumbPosition = .unknown
        var thumbPositionViewFrame: CGRect = .zero
        for (position, area) in caculateThumbAreas() {
            if area.contains(touchPoint) {
                thumbPosition = position
                thumbPositionViewFrame = area
            }
        }
        
        if isDebug && thumbPosition != .unknown {
            thumbPositionView.isHidden = false
            thumbPositionView.frame = thumbPositionViewFrame
        }
        
        delegate?.resizeViewThumbOn(self)
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touchPoint = touches.first?.location(in: self),
            let previous = touches.first?.previousLocation(in: self) else {
                return
        }
        
        let deltaWidth =  previous.x - touchPoint.x
        let deltaHeight = previous.y - touchPoint.y

        let originX = frame.origin.x
        let originY = frame.origin.y
        let width = frame.size.width
        let height = frame.size.height
        
        let originFrame = frame
        var finalFrame = originFrame
        
        switch thumbPosition {
        case .upLeftCorner:
            let scaleX = 1.0 - (-deltaWidth / width)
            let scaleY = 1.0 - (-deltaHeight / height)
            
            finalFrame.size.width = width * scaleX
            finalFrame.size.height = height * scaleY
            finalFrame.origin.x = originX + width - finalFrame.size.width
            finalFrame.origin.y = originY + height - finalFrame.size.height
        case .upSide:
            let scaleY = 1.0 - (-deltaHeight / height)

            finalFrame.size.height = height * scaleY
            finalFrame.origin.y = originY + height - finalFrame.size.height
        case .upRightCorner:
            let scaleX = 1.0 - (deltaWidth / width)
            let scaleY = 1.0 - (-deltaHeight / height)

            finalFrame.size.width = width * scaleX
            finalFrame.size.height = height * scaleY
            finalFrame.origin.y = originY + height - finalFrame.size.height
        case .rightSide:
            let scaleX = 1.0 - (deltaWidth / width)

            finalFrame.size.width = width * scaleX
        case .downRightCorner:
            let scaleX = 1.0 - (deltaWidth / width)
            let scaleY = 1.0 - (deltaHeight / height)
            
            finalFrame.size.width = width * scaleX
            finalFrame.size.height = height * scaleY
        case .downSide:
            let scaleY = 1.0 - (deltaHeight / height)
            
            finalFrame.size.height = height * scaleY
        case .downLeftCorner:
            let scaleX = 1.0 - (-deltaWidth / width)
            let scaleY = 1.0 - (deltaHeight / height)
            
            finalFrame.size.width = width * scaleX
            finalFrame.size.height = height * scaleY
            finalFrame.origin.x = originX + width - finalFrame.size.width
        case .leftSide:
            let scaleX = 1.0 - (-deltaWidth / width)
            
            finalFrame.size.width = width * scaleX
            finalFrame.origin.x = originX + width - finalFrame.size.width
        case .unknown:
            break
        }

        if finalFrame.maxX <= maxFrame.maxX &&
            finalFrame.minX >= maxFrame.minX &&
            finalFrame.maxY <= maxFrame.maxY &&
            finalFrame.minY >= maxFrame.minY &&
            finalFrame.maxX - finalFrame.minX >= minSize &&
            finalFrame.maxY - finalFrame.minY >= minSize {
            frame = finalFrame
            delegate?.resizeView(self, didResize: cropRect)
        }
        
        if isDebug && thumbPosition != .unknown {
            thumbPositionView.isHidden = true
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.resizeViewThumbOff(self)
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        delegate?.resizeViewThumbOff(self)
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if bounds.contains(point) {
            for area in caculateThumbAreas().values {
                if area.contains(point) {
                    return true
                }
            }
        }
        return false
    }
    
    private func caculateThumbAreas() -> [ThumbPosition: CGRect] {
        var thumbAreas: [ThumbPosition: CGRect] = [:]
        
        let thumbPadding = framePadding + frameShortSide + frameBorderWidth - thumbSize / 2.0
        let boundsWidth = bounds.width - thumbPadding * 2
        let boundsHeight = bounds.height - thumbPadding * 2
        
        let upLeftCorner = CGRect(x: thumbPadding, y: thumbPadding, width: thumbSize, height: thumbSize)
        thumbAreas[.upLeftCorner] = upLeftCorner
        thumbAreas[.upRightCorner] = upLeftCorner.applying(.init(translationX: boundsWidth - thumbSize, y: 0))
        thumbAreas[.downRightCorner] = upLeftCorner.applying(.init(translationX: boundsWidth - thumbSize,
                                                          y: boundsHeight - thumbSize))
        thumbAreas[.downLeftCorner] = upLeftCorner.applying(.init(translationX: 0, y: boundsHeight - thumbSize))
        let upSide = CGRect(x: thumbPadding + thumbSize, y: thumbPadding,
                            width: boundsWidth - thumbSize * 2, height: thumbSize)
        thumbAreas[.upSide] = upSide
        thumbAreas[.downSide] = upSide.applying(.init(translationX: 0, y: boundsHeight - thumbSize))
        let leftSide = CGRect(x: thumbPadding, y: thumbPadding + thumbSize,
                              width: thumbSize, height: boundsHeight - thumbSize * 2)
        thumbAreas[.leftSide] = leftSide
        thumbAreas[.rightSide] = leftSide.applying(.init(translationX: boundsWidth - thumbSize, y: 0))
        
        return thumbAreas
    }
    
}

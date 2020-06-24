//
//  EffectFilter.swift
//  DTCamera
//
//  Created by Dan Jiang on 2019/9/27.
//  Copyright © 2019 Dan Thought Studio. All rights reserved.
//

import UIKit
import CoreMedia

protocol EffectFilter {
    var outputFormatDescription: CMFormatDescription? { get }
    
    func prepare(with ratioMode: CameraRatioMode, positionMode: CameraPositionMode,
                 formatDescription: CMFormatDescription, retainedBufferCountHint: Int)
    func filter(pixelBuffer: CVPixelBuffer) -> CVPixelBuffer
    func addEmitter(x: CGFloat, y: CGFloat)
}
